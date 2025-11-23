# src/model_loader.py
import logging
import os
import torch
from diffusers import AutoPipelineForText2Image

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
    torch_dtype = torch.float16 if device == "cuda" else torch.float32

    # Prefer local model dir if present (SageMaker puts model.tar.gz under /opt/ml/model)
    model_dir = os.getenv("MODEL_DIR", "/opt/ml/model")

    if os.path.exists(os.path.join(model_dir, "model_index.json")):
        model_id = model_dir
        logger.info(f"Loading pipeline from local dir: {model_id}")
    else:
        # Fallback to HF hub (for local dev / non-SM usage)
        model_id = "stabilityai/sdxl-turbo"
        logger.info(f"Local model not found, loading from hub: {model_id}")

    pipe = AutoPipelineForText2Image.from_pretrained(
        model_id,
        torch_dtype=torch_dtype,
        low_cpu_mem_usage=True,
        local_files_only=os.path.isdir(model_dir),  # avoid hub if we know it's local
    ).to(device)

    _pipe = pipe
    return _pipe