# src/inference_handler.py
# Pure SageMaker inference handler - no authentication logic
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import base64
from io import BytesIO
from src.model_loader import get_pipeline
import torch
from contextlib import nullcontext
import logging
import json
import os
from datetime import datetime

try:
    import boto3
    from botocore.exceptions import ClientError
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False
    boto3 = None

try:
    from torch.cuda.amp import autocast
    HAS_CUDA_AMP = True
except Exception:
    HAS_CUDA_AMP = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="SDXL-Turbo Inference Service",
    description="SageMaker inference service for SDXL-Turbo image generation",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Simple Prompt model for the predict endpoint
class Prompt(BaseModel):
    prompt: str


@app.on_event("startup")
async def startup_event():
    """Load and warm up model on startup for SageMaker inference"""
    logger.info("SageMaker inference service starting with optimized model loading...")
    
    # Load model with optimizations and warmup
    try:
        get_pipeline()
        logger.info("✅ Model loaded, warmed up, and ready for inference!")
    except Exception as e:
        logger.error(f"❌ Model loading failed: {e}")
        raise e  # Let SageMaker know startup failed


@app.get("/ping")
async def ping():
    """SageMaker health check endpoint - should return 200 when service is ready"""
    return {"status": "ok", "service": "sagemaker-inference"}


@app.post("/predict")
async def predict(data: Prompt):
    """Standard inference endpoint"""
    return await _run_inference(data.prompt)


@app.post("/invocations")
async def invocations(request: Request):
    """
    SageMaker async inference endpoint.
    
    For ASYNC inference:
    - SageMaker downloads input from S3 and sends to this endpoint
    - We return JSON response
    - SageMaker uploads our response to S3 output location

    Supports:
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
        result["inference_metadata"] = {
            "model": "sdxl-turbo",
            "timestamp": datetime.utcnow().isoformat(),
            "content_type": content_type
        }

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