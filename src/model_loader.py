import torch
from diffusers import AutoPipelineForText2Image
import logging

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
    logger.info("Creating global pipeline...")
    global _pipe

    if _pipe is not None:
        return _pipe

    device = get_device()
    logger.info("setting dtype...")
    dtype = torch.float16 if device == "cuda" else torch.float32

    logger.info(f"Loading SDXL pipeline on {device} ({dtype}) …")
    pipe = AutoPipelineForText2Image.from_pretrained(
        "stabilityai/sdxl-turbo",
        dtype=dtype,
    ).to(device)

    if device == "cuda":
        logger.info("model loader using cuda...")
        from torch.cuda.amp import autocast
        logger.info("Warming up model…")
        with torch.inference_mode(), autocast("cuda"):
            pipe("warmup", num_inference_steps=2, guidance_scale=0.0)
    else:
        # Optional CPU warmup (slow)
        logger.info("Warming up model (CPU)…")
        with torch.inference_mode():
            pipe("warmup", num_inference_steps=2, guidance_scale=0.0)

    _pipe = pipe
    return _pipe