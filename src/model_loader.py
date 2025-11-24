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

    # Check for model location in environment variables
    model_s3_location = os.getenv("MODEL_S3_LOCATION")
    model_dir = os.getenv("MODEL_DIR", "/opt/ml/model")

    if os.path.exists(os.path.join(model_dir, "model_index.json")):
        # SageMaker extracts model.tar.gz to /opt/ml/model automatically
        model_id = model_dir
        logger.info(f"Loading pipeline from SageMaker model dir: {model_id}")
        if model_s3_location:
            logger.info(f"Model was loaded from S3: {model_s3_location}")
        local_files_only = True
    elif os.path.exists(model_dir) and os.listdir(model_dir):
        # Model dir exists and has files
        model_id = model_dir
        logger.info(f"Loading pipeline from local dir: {model_id}")
        local_files_only = True
    else:
        # Fallback to HF hub (for local dev only)
        model_id = "stabilityai/sdxl-turbo"
        logger.info(f"No local model found, loading from HuggingFace hub: {model_id}")
        if model_s3_location:
            logger.warning(f"MODEL_S3_LOCATION is set to {model_s3_location} but model not found in {model_dir}")
        local_files_only = False

    pipe = AutoPipelineForText2Image.from_pretrained(
        model_id,
        torch_dtype=torch_dtype,
        low_cpu_mem_usage=True,
        local_files_only=local_files_only,
    ).to(device)

    _pipe = pipe
    return _pipe