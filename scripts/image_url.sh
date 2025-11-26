 #!/bin/bash
  set -e  # Exit on any error

  echo "Invoking async endpoint..."
  RESPONSE=$(aws sagemaker-runtime invoke-endpoint-async \
    --endpoint-name "model-harness-endpoint" \
    --input-location "s3://model-harness-io/input.json" \
    --content-type "application/json")

  echo "Getting output location..."
  OUTPUT_LOCATION=$(echo $RESPONSE | jq -r '.OutputLocation')
  echo "Output will be at: $OUTPUT_LOCATION"

  echo "Waiting for processing to complete..."
  sleep 5  # Wait for inference to complete

  echo "Generating presigned URL..."
  PRESIGNED_URL=$(aws s3 presign "$OUTPUT_LOCATION" --expires-in 3600)
  echo $PRESIGNED_URL

  echo "Downloading result..."
  curl "$PRESIGNED_URL" -o result.json

  echo "Extracting image..."
  cat result.json | jq -r '.image' | base64 -d > generated_image.png

  echo "Done! Image saved as generated_image.png"