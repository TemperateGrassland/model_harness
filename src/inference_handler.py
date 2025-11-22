from fastapi import FastAPI
from pydantic import BaseModel
import base64
from io import BytesIO
from src.model_loader import get_pipeline
import torch
from contextlib import nullcontext
import logging

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
    get_pipeline()


@app.post("/predict")
async def predict(data: Prompt):
    logger.info("/predict endpoint recieved request")

    pipe = get_pipeline()

    if HAS_CUDA_AMP and torch.cuda.is_available():
        ctx = autocast("cuda")
        logger.info("Using cuda...")
    else:
        ctx = nullcontext()

    with torch.inference_mode(), ctx:
        logger.info("Beginning inference...")
        result = pipe(data.prompt, num_inference_steps=10, guidance_scale=0.0)

    image = result.images[0]

    buffer = BytesIO()
    logger.info("Saving as PNG (this could be jpeg) to optimise if quality is ok...")
    image.save(buffer, format="PNG")
    logger.info("base64 enconding model output (returning binary or outputing to s3 could optimise this)...")
    encoded = base64.b64encode(buffer.getvalue()).decode("utf-8")

    return {"image": encoded}