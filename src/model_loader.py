import logging
import os

import torch
from diffusers import AutoPipelineForText2Image

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

_pipe = None


def get_device() -> str:
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def get_pipeline():
    global _pipe
    if _pipe is not None:
        return _pipe

    device = get_device()

    # Use a smaller model on CPU so local Docker runs don't OOM,
    # but keep SDXL-turbo for real GPU deployments.
    if device == "cuda":
        model_id = os.getenv("MODEL_ID", "stabilityai/sdxl-turbo")
        torch_dtype = torch.float16
    else:
        # Lighter pipeline for local dev on CPU
        model_id = os.getenv("MODEL_ID", "stabilityai/sd-turbo")
        torch_dtype = torch.float32

    logger.info(f"Loading pipeline {model_id} on {device} ({torch_dtype}) …")

    pipe = AutoPipelineForText2Image.from_pretrained(
        model_id,
        torch_dtype=torch_dtype,
        low_cpu_mem_usage=True,
    )

    pipe = pipe.to(device)

    logger.info("Warming up model…")
    if device == "cuda":
        from torch.cuda.amp import autocast
        with torch.inference_mode(), autocast("cuda"):
            pipe("warmup", num_inference_steps=2, guidance_scale=0.0)
    else:
        with torch.inference_mode():
            pipe("warmup", num_inference_steps=2, guidance_scale=0.0)

    _pipe = pipe
    logger.info("Pipeline ready.")
    return _pipe