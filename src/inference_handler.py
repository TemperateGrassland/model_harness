# src/inference_handler.py
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
import base64
from io import BytesIO
from src.model_loader import get_pipeline
import torch
from contextlib import nullcontext
import logging
import json
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

app = FastAPI()

try:
    from torch.cuda.amp import autocast
    HAS_CUDA_AMP = True
except Exception:
    HAS_CUDA_AMP = False


class Prompt(BaseModel):
    prompt: str


@app.on_event("startup")
async def startup_event():
    # For async endpoints that scale to zero, you *can* keep this warmup,
    # accepting a slower cold start but faster first inference.
    get_pipeline()


@app.get("/ping")
async def ping():
    # Simple health check for SageMaker
    try:
        _ = get_pipeline()
        return {"status": "ok"}
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
        result["inference_metadata"] = {
            "model": "sdxl-turbo",
            "timestamp": logger.handlers[0].formatter.formatTime(logging.LogRecord(
                name="", level=0, pathname="", lineno=0, msg="", args=(), exc_info=None
            )),
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