# Use a smaller image for faster builds, we only need runtime
FROM nvidia/cuda:12.3.0-devel-ubuntu22.04

RUN apt-get update && apt-get install -y python3 python3-pip git wget curl && apt-get clean

WORKDIR /app

COPY docker/requirements.txt .

# Combine RUN cmds into one line to reduce layers
RUN pip3 install --upgrade pip &&  pip3 install -r requirements.txt

# Can I afford to remove the app.py from the final docker image?
COPY src/ /app/src
COPY sagemaker/serve.sh /usr/local/bin/serve
RUN chmod +x /usr/local/bin/serve

ENV PYTHONPATH=/app/src
ENV MODEL_DIR=/opt/ml/model

# Define an entrypoint to ensure python executable is always used
ENTRYPOINT ["python"]
# default command
CMD ["serve"]
