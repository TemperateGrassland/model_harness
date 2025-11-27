# src/inference_handler.py
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import base64
from io import BytesIO
from src.model_loader import get_pipeline
from src.auth import get_current_user, authenticator, AuthError, RateLimitError
from src.errors import (
    APIError, ValidationAPIError, InferenceAPIError, ServiceUnavailableAPIError,
    auth_error_handler, api_error_handler, general_error_handler, CircuitBreaker
)
import torch
from contextlib import nullcontext
import logging
import json
import uuid
import os
from datetime import datetime
from typing import Optional, Dict, Any
try:
    import boto3
    from botocore.exceptions import ClientError
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False
    boto3 = None

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="AI Image Generation API",
    description="Authenticated async image generation using SDXL-Turbo",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Add error handlers
app.add_exception_handler(AuthError, auth_error_handler)
app.add_exception_handler(RateLimitError, auth_error_handler)
app.add_exception_handler(APIError, api_error_handler)
app.add_exception_handler(Exception, general_error_handler)

try:
    from torch.cuda.amp import autocast
    HAS_CUDA_AMP = True
except Exception:
    HAS_CUDA_AMP = False


class Prompt(BaseModel):
    prompt: str


@app.on_event("startup")
async def startup_event():
    # Only load model if running in SageMaker (has SM_MODEL_DIR)
    # ECS containers skip model loading since they're just auth proxies
    if os.getenv("SM_MODEL_DIR"):
        logger.info("Running in SageMaker - loading model for inference")
        get_pipeline()
    else:
        logger.info("Running in ECS - skipping model load (auth proxy mode)")


@app.get("/ping")
async def ping():
    # Health check - conditional model check
    try:
        if os.getenv("SM_MODEL_DIR"):
            # SageMaker: Check model is loaded
            _ = get_pipeline()
            return {"status": "ok", "mode": "sagemaker"}
        else:
            # ECS: Just return OK (no model needed)
            return {"status": "ok", "mode": "ecs-auth-proxy"}
    except Exception as e:
        logger.exception("Ping failed")
        return {"status": "error", "detail": str(e)}


@app.post("/predict")
async def predict(data: Prompt):
    return await _run_inference(data.prompt)


@app.post("/invocations")
async def invocations(request: Request):
    """
    SageMaker will POST to /invocations.
    
    For ASYNC inference:
    - SageMaker downloads input from S3 and sends to this endpoint
    - We return JSON response
    - SageMaker uploads our response to S3 output location

    We support:
      - application/json: { "prompt": "..." } or { "input_s3_uri": "s3://..." }
      - text/plain: raw prompt string
    """
    content_type = request.headers.get("content-type", "")
    
    try:
        if "application/json" in content_type:
            body = await request.json()
            
            # Support both direct prompt and S3 input reference
            if "input_s3_uri" in body:
                prompt = await _read_from_s3(body["input_s3_uri"])
            elif "prompt" in body:
                prompt = body["prompt"]
            else:
                raise HTTPException(status_code=400, detail="Request must contain 'prompt' or 'input_s3_uri'")
                
        elif "text/plain" in content_type:
            prompt = (await request.body()).decode("utf-8")
        else:
            # Default: try JSON
            body = await request.json()
            if "input_s3_uri" in body:
                prompt = await _read_from_s3(body["input_s3_uri"])
            elif "prompt" in body:
                prompt = body["prompt"]
            else:
                raise HTTPException(status_code=400, detail="Request must contain 'prompt' or 'input_s3_uri'")

        result = await _run_inference(prompt)
        
        # Add metadata for async inference tracking
        from datetime import datetime
        result["inference_metadata"] = {
            "model": "sdxl-turbo",
            "timestamp": datetime.utcnow().isoformat(),
            "content_type": content_type
        }

        # For async endpoints, SageMaker will write whatever we return to S3
        return result
        
    except Exception as e:
        logger.exception(f"Error in async inference: {e}")
        # Return error in format SageMaker can handle
        return {
            "error": str(e),
            "status": "failed",
            "inference_metadata": {
                "model": "sdxl-turbo",
                "error_type": type(e).__name__
            }
        }


async def _run_inference(prompt: str):
    """Run SDXL-Turbo inference on the given prompt."""
    logger.info(f"Inference request received for prompt: {prompt[:50]}...")

    if not prompt or not prompt.strip():
        raise ValueError("Prompt cannot be empty")

    pipe = get_pipeline()

    if HAS_CUDA_AMP and torch.cuda.is_available():
        ctx = autocast(enabled=True)
        logger.info("Using CUDA with autocast...")
    else:
        ctx = nullcontext()
        logger.info("Using CPU inference...")

    with torch.inference_mode(), ctx:
        logger.info("Beginning SDXL-Turbo inference...")
        result = pipe(
            prompt, 
            num_inference_steps=10, 
            guidance_scale=0.0,  # Required for SDXL-Turbo
            height=512,
            width=512
        )

    image = result.images[0]

    buffer = BytesIO()
    logger.info("Saving generated image as PNG...")
    image.save(buffer, format="PNG")
    logger.info("Base64 encoding model output...")
    encoded = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    logger.info("Inference completed successfully")
    return {
        "image": encoded,
        "format": "png",
        "size": {"width": 512, "height": 512},
        "prompt": prompt
    }


async def _read_from_s3(s3_uri: str) -> str:
    """Read input from S3 URI for async inference."""
    if not HAS_BOTO3:
        raise ImportError("boto3 is required for S3 operations")
        
    logger.info(f"Reading input from S3: {s3_uri}")
    
    # Parse S3 URI
    if not s3_uri.startswith("s3://"):
        raise ValueError("Invalid S3 URI format. Must start with s3://")
        
    s3_path = s3_uri[5:]  # Remove 's3://'
    bucket, key = s3_path.split("/", 1)
    
    try:
        s3_client = boto3.client("s3")
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response["Body"].read().decode("utf-8")
        
        # Try to parse as JSON first
        try:
            data = json.loads(content)
            if "prompt" in data:
                return data["prompt"]
            else:
                raise ValueError("S3 input JSON must contain 'prompt' field")
        except json.JSONDecodeError:
            # Treat as plain text prompt
            return content.strip()
            
    except ClientError as e:
        logger.error(f"Failed to read from S3: {e}")
        raise HTTPException(status_code=400, detail=f"Failed to read from S3: {e}")
    except Exception as e:
        logger.error(f"Unexpected error reading from S3: {e}")
        raise HTTPException(status_code=500, detail=f"S3 read error: {e}")


# ============================================================================
# AUTHENTICATED ASYNC ENDPOINTS
# ============================================================================

class AsyncGenerateRequest(BaseModel):
    prompt: str
    priority: Optional[str] = "normal"  # normal, high
    callback_url: Optional[str] = None

class AsyncGenerateResponse(BaseModel):
    job_id: str
    inference_id: str
    output_location: str
    failure_location: str
    estimated_completion_seconds: int
    status_url: str
    user_id: str

class JobStatus(BaseModel):
    job_id: str
    status: str  # pending, processing, completed, failed
    created_at: str
    completed_at: Optional[str]
    output_url: Optional[str]
    error_message: Optional[str]
    user_id: str

# Circuit breaker for SageMaker calls
sagemaker_circuit_breaker = CircuitBreaker(failure_threshold=5, reset_timeout=60)

@app.post("/auth/generate", response_model=AsyncGenerateResponse)
async def authenticated_async_generate(
    request: AsyncGenerateRequest,
    current_user: Dict[str, Any] = Depends(get_current_user)
) -> AsyncGenerateResponse:
    """
    Authenticated async image generation endpoint
    
    Requires JWT token in Authorization header.
    Uploads prompt to S3, invokes SageMaker async endpoint, returns job tracking info.
    """
    try:
        user_id = current_user.get("user_id")
        job_id = str(uuid.uuid4())
        
        logger.info(f"Starting async generation for user {user_id}, job {job_id}")
        
        if not request.prompt or not request.prompt.strip():
            raise ValidationAPIError("Prompt cannot be empty")
        
        if len(request.prompt) > 1000:
            raise ValidationAPIError("Prompt too long (max 1000 characters)")
        
        # Create S3 input
        bucket = os.getenv('S3_BUCKET_NAME', 'model-harness-io')
        input_key = f"inputs/{user_id}/{job_id}.json"
        input_s3_uri = f"s3://{bucket}/{input_key}"
        
        # Upload input to S3
        input_data = {
            "prompt": request.prompt,
            "user_id": user_id,
            "job_id": job_id,
            "priority": request.priority,
            "callback_url": request.callback_url,
            "created_at": datetime.utcnow().isoformat()
        }
        
        if not HAS_BOTO3:
            raise ServiceUnavailableAPIError("AWS services unavailable")
        
        s3_client = boto3.client('s3')
        s3_client.put_object(
            Bucket=bucket,
            Key=input_key,
            Body=json.dumps(input_data),
            ContentType='application/json',
            Metadata={
                'user_id': user_id,
                'job_id': job_id,
                'priority': request.priority
            }
        )
        
        # Invoke SageMaker async endpoint
        endpoint_name = os.getenv('SAGEMAKER_ENDPOINT_NAME', 'model-harness-endpoint')
        
        response = await _invoke_sagemaker_async(endpoint_name, input_s3_uri)
        
        # Build response
        status_url = f"/auth/status/{job_id}"
        
        result = AsyncGenerateResponse(
            job_id=job_id,
            inference_id=response['InferenceId'],
            output_location=response['OutputLocation'],
            failure_location=response['FailureLocation'],
            estimated_completion_seconds=5,
            status_url=status_url,
            user_id=user_id
        )
        
        logger.info(f"Async generation started for user {user_id}, job {job_id}, inference {response['InferenceId']}")
        return result
        
    except ValidationAPIError:
        raise
    except Exception as e:
        logger.exception(f"Error in async generation for user {user_id}: {e}")
        raise InferenceAPIError(f"Failed to start image generation: {str(e)}")

@app.get("/auth/status/{job_id}", response_model=JobStatus)
async def get_job_status(
    job_id: str,
    current_user: Dict[str, Any] = Depends(get_current_user)
) -> JobStatus:
    """Get status of an async generation job"""
    try:
        user_id = current_user.get("user_id")
        
        # Check S3 for job completion
        bucket = os.getenv('S3_BUCKET_NAME', 'model-harness-io')
        output_prefix = f"outputs/"
        failure_prefix = f"failures/"
        
        s3_client = boto3.client('s3')
        
        # Look for output file (completed)
        try:
            output_objects = s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix=output_prefix,
                MaxKeys=100
            )
            
            for obj in output_objects.get('Contents', []):
                if job_id in obj['Key']:
                    # Generate presigned URL for download
                    presigned_url = s3_client.generate_presigned_url(
                        'get_object',
                        Params={'Bucket': bucket, 'Key': obj['Key']},
                        ExpiresIn=3600
                    )
                    
                    return JobStatus(
                        job_id=job_id,
                        status="completed",
                        created_at=obj['LastModified'].isoformat(),
                        completed_at=obj['LastModified'].isoformat(),
                        output_url=presigned_url,
                        error_message=None,
                        user_id=user_id
                    )
        except Exception as e:
            logger.warning(f"Error checking output status: {e}")
        
        # Look for failure file
        try:
            failure_objects = s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix=failure_prefix,
                MaxKeys=100
            )
            
            for obj in failure_objects.get('Contents', []):
                if job_id in obj['Key']:
                    # Read error details
                    error_response = s3_client.get_object(Bucket=bucket, Key=obj['Key'])
                    error_content = error_response['Body'].read().decode('utf-8')
                    
                    return JobStatus(
                        job_id=job_id,
                        status="failed",
                        created_at=obj['LastModified'].isoformat(),
                        completed_at=obj['LastModified'].isoformat(),
                        output_url=None,
                        error_message=error_content[:500],  # Truncate long errors
                        user_id=user_id
                    )
        except Exception as e:
            logger.warning(f"Error checking failure status: {e}")
        
        # Default to processing
        return JobStatus(
            job_id=job_id,
            status="processing",
            created_at=datetime.utcnow().isoformat(),
            completed_at=None,
            output_url=None,
            error_message=None,
            user_id=user_id
        )
        
    except Exception as e:
        logger.exception(f"Error getting job status for {job_id}: {e}")
        raise InferenceAPIError(f"Failed to get job status: {str(e)}")

@app.post("/auth/token")
async def create_auth_token(user_id: str) -> Dict[str, str]:
    """Create JWT token for testing purposes (remove in production)"""
    if not user_id:
        raise ValidationAPIError("user_id is required")
    
    token = authenticator.create_jwt_token(user_id, expires_in_hours=24)
    
    return {
        "access_token": token,
        "token_type": "bearer",
        "expires_in": 86400,  # 24 hours
        "user_id": user_id
    }

@sagemaker_circuit_breaker
async def _invoke_sagemaker_async(endpoint_name: str, input_s3_uri: str) -> Dict[str, str]:
    """Invoke SageMaker async endpoint with circuit breaker"""
    try:
        sagemaker_runtime = boto3.client('sagemaker-runtime')
        response = sagemaker_runtime.invoke_endpoint_async(
            EndpointName=endpoint_name,
            InputLocation=input_s3_uri,
            ContentType='application/json'
        )
        return response
    except Exception as e:
        logger.error(f"SageMaker invocation failed: {e}")
        raise InferenceAPIError(f"SageMaker invocation failed: {str(e)}")

# Health check with optional auth
@app.get("/auth/health")
async def authenticated_health_check(
    current_user: Dict[str, Any] = Depends(get_current_user)
) -> Dict[str, Any]:
    """Health check that requires authentication"""
    user_id = current_user.get("user_id")
    
    # Check model status based on environment
    if os.getenv("SM_MODEL_DIR"):
        # SageMaker: Check actual model
        try:
            _ = get_pipeline()
            model_status = "ready"
        except Exception as e:
            logger.error(f"Model health check failed: {e}")
            model_status = "error"
    else:
        # ECS: No model needed
        model_status = "not-required-auth-proxy"
    
    # Check Redis connection
    redis_status = "connected" if authenticator.redis_client else "disconnected"
    
    return {
        "status": "ok",
        "user_id": user_id,
        "timestamp": datetime.utcnow().isoformat(),
        "model_status": model_status,
        "redis_status": redis_status,
        "services": {
            "sagemaker": "available" if HAS_BOTO3 else "unavailable",
            "s3": "available" if HAS_BOTO3 else "unavailable"
        }
    }