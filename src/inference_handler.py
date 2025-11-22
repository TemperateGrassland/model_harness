# src/inference_handler.py
from fastapi import FastAPI, Request
from pydantic import BaseModel
import base64
from io import BytesIO
from src.model_loader import get_pipeline
import torch
from contextlib import nullcontext
import logging
import json

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
    autocast = None
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

    We support:
      - application/json: { "prompt": "..." }
      - text/plain: raw prompt string
    """
    content_type = request.headers.get("content-type", "")

    if "application/json" in content_type:
        body = await request.json()
        prompt = body["prompt"]
    elif "text/plain" in content_type:
        prompt = (await request.body()).decode("utf-8")
    else:
        # Default: try JSON
        body = await request.json()
        prompt = body["prompt"]

    result = await _run_inference(prompt)

    # For async endpoints, SageMaker will write whatever we return
    # to S3. Returning JSON with base64 is fine.
    return result


async def _run_inference(prompt: str):
    logger.info("Inference request received")

    pipe = get_pipeline()

    if HAS_CUDA_AMP and torch.cuda.is_available():
        ctx = autocast("cuda")
        logger.info("Using cuda...")
    else:
        ctx = nullcontext()

    with torch.inference_mode(), ctx:
        logger.info("Beginning inference...")
        result = pipe(prompt, num_inference_steps=10, guidance_scale=0.0)

    image = result.images[0]

    buffer = BytesIO()
    logger.info("Saving as PNG...")
    image.save(buffer, format="PNG")
    logger.info("Base64 encoding model output...")
    encoded = base64.b64encode(buffer.getvalue()).decode("utf-8")

    return {"image": encoded}