# Use a smaller image for faster builds, we only need runtime
FROM nvidia/cuda:12.3.0-devel-ubuntu22.04

# Install python3
RUN apt-get update && apt-get install -y python3 python3-pip git wget curl && apt-get clean
# install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /app

COPY pyproject.toml /app/
COPY uv.lock /app/
RUN uv sync --frozen --no-dev

ENV VIRTUAL_ENV=/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
# Ensure cached models are used
ENV HF_HUB_OFFLINE=1
ENV HF_HOME=/root/.cache/huggingface

# Pre-download the models so runtime doesn't need internet
RUN python3 -c "from diffusers import AutoPipelineForText2Image; \
    AutoPipelineForText2Image.from_pretrained('stabilityai/sd-turbo')"

# If you want SDXL for GPU runtime:
RUN python3 -c "from diffusers import AutoPipelineForText2Image; \
    AutoPipelineForText2Image.from_pretrained('stabilityai/sdxl-turbo')"


# Can I afford to remove the app.py from the final docker image?
COPY src/ /app/src
COPY sagemaker/serve.sh /usr/local/bin/serve
RUN chmod +x /usr/local/bin/serve

ENV PYTHONPATH=/app/src
ENV MODEL_DIR=/opt/ml/model

# Define an entrypoint to ensure python executable is always used
ENTRYPOINT ["bash", "/usr/local/bin/serve"]
# default command
# CMD ["/usr/local/bin/serve"]
