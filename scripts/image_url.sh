#!/bin/bash
set -e  # Exit on any error

# Configuration
BUCKET="model-harness-io"
ENDPOINT_NAME="model-harness-endpoint"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS] \"<prompt>\""
    echo ""
    echo "Generate an image using SageMaker async endpoint with the given prompt"
    echo ""
    echo "Arguments:"
    echo "  prompt                The text prompt for image generation (required)"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -o, --output FILE    Output image filename (default: generated_image.png)"
    echo "  -w, --wait SECONDS   Wait time for processing (default: 60)"
    echo ""
    echo "Examples:"
    echo "  $0 \"a cat astronaut on the moon\""
    echo "  $0 -o space_cat.png \"a futuristic cat floating in the clouds\""
    echo "  $0 -w 120 \"a dragon breathing fire in a medieval castle\""
}

# Default values
OUTPUT_FILE="generated_image.png"
WAIT_TIME=5

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -w|--wait)
            WAIT_TIME="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$PROMPT" ]]; then
                PROMPT="$1"
            else
                print_error "Multiple prompts provided. Please provide only one prompt."
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if prompt is provided, if not prompt user interactively
if [[ -z "$PROMPT" ]]; then
    echo ""
    print_status "No prompt provided. Let's create one interactively!"
    echo ""
    
    # Interactive prompt
    while [[ -z "$PROMPT" ]]; do
        echo -n -e "${YELLOW}Enter your image generation prompt: ${NC}"
        read -r USER_INPUT
        
        if [[ -n "$USER_INPUT" ]]; then
            PROMPT="$USER_INPUT"
        else
            print_error "Prompt cannot be empty. Please try again."
            echo ""
        fi
    done
    
    echo ""
    print_success "Great! Using prompt: \"$PROMPT\""
    echo ""
    
    # Ask for output filename
    echo -n -e "${YELLOW}Enter output filename (press Enter for default 'generated_image.png'): ${NC}"
    read -r USER_OUTPUT
    
    if [[ -n "$USER_OUTPUT" ]]; then
        # Add .png extension if not provided
        if [[ "$USER_OUTPUT" != *.png ]]; then
            USER_OUTPUT="${USER_OUTPUT}.png"
        fi
        OUTPUT_FILE="$USER_OUTPUT"
    fi
    
    echo ""
    print_status "Output will be saved as: $OUTPUT_FILE"
    echo ""
fi

# Check required tools
for cmd in aws jq curl base64; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is required but not installed"
        exit 1
    fi
done

# Generate unique input filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
INPUT_KEY="inputs/input_${TIMESTAMP}.json"
INPUT_S3_URI="s3://${BUCKET}/${INPUT_KEY}"

print_status "Starting image generation with SageMaker async endpoint"
print_status "Prompt: \"$PROMPT\""
print_status "Output file: $OUTPUT_FILE"
echo ""

# Step 1: Create input JSON and upload to S3
print_status "Creating input JSON and uploading to S3..."
INPUT_JSON="{\"prompt\": \"$PROMPT\"}"
echo "$INPUT_JSON" > /tmp/input_${TIMESTAMP}.json

aws s3 cp /tmp/input_${TIMESTAMP}.json "$INPUT_S3_URI" --quiet
rm /tmp/input_${TIMESTAMP}.json

print_success "Input uploaded to: $INPUT_S3_URI"

# Step 2: Invoke async endpoint
print_status "Invoking SageMaker async endpoint..."
RESPONSE=$(aws sagemaker-runtime invoke-endpoint-async \
    --endpoint-name "$ENDPOINT_NAME" \
    --input-location "$INPUT_S3_URI" \
    --content-type "application/json")

# Extract output location and inference ID
OUTPUT_LOCATION=$(echo "$RESPONSE" | jq -r '.OutputLocation')
FAILURE_LOCATION=$(echo "$RESPONSE" | jq -r '.FailureLocation')
INFERENCE_ID=$(echo "$RESPONSE" | jq -r '.InferenceId')

print_success "Inference submitted successfully!"
print_status "Inference ID: $INFERENCE_ID"
print_status "Output location: $OUTPUT_LOCATION"

# Step 3: Poll for completion
print_status "Polling for completion (checking every 2 seconds, max ${WAIT_TIME}s)..."
ELAPSED=0
POLL_INTERVAL=2

while [ $ELAPSED -lt $WAIT_TIME ]; do
    printf "\r${BLUE}[INFO]${NC} Checking... ${ELAPSED}/${WAIT_TIME}s"
    
    # Check if output is ready
    if aws s3 ls "$OUTPUT_LOCATION" &>/dev/null; then
        printf "\n"
        print_success "Output file is ready after ${ELAPSED}s!"
        break
    fi
    
    # Check if failed
    if aws s3 ls "$FAILURE_LOCATION" &>/dev/null; then
        printf "\n"
        print_error "Inference failed after ${ELAPSED}s!"
        print_status "Downloading failure details..."
        aws s3 cp "$FAILURE_LOCATION" /tmp/failure_${TIMESTAMP}.json --quiet
        
        print_error "Failure details:"
        cat /tmp/failure_${TIMESTAMP}.json | jq '.' || cat /tmp/failure_${TIMESTAMP}.json
        rm /tmp/failure_${TIMESTAMP}.json
        exit 1
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done
printf "\n"

# Step 4: Download if ready
if aws s3 ls "$OUTPUT_LOCATION" &>/dev/null; then
    # Step 5: Generate presigned URL and download
    print_status "Generating presigned URL..."
    PRESIGNED_URL=$(aws s3 presign "$OUTPUT_LOCATION" --expires-in 3600)
    
    print_success "Presigned URL (valid for 1 hour, reusable):"
    echo "$PRESIGNED_URL"
    echo ""
    
    print_status "Downloading result..."
    curl -s "$PRESIGNED_URL" -o /tmp/result_${TIMESTAMP}.json
    
    # Step 6: Extract and save image
    print_status "Extracting image data..."
    if cat /tmp/result_${TIMESTAMP}.json | jq -r '.image' | base64 -d > "$OUTPUT_FILE" 2>/dev/null; then
        rm /tmp/result_${TIMESTAMP}.json
        
        # Get image info
        IMAGE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
        
        print_success "Image generated successfully!"
        print_success "Saved as: $OUTPUT_FILE (${IMAGE_SIZE})"
        print_status "Prompt used: \"$PROMPT\""
        
        # Optional: Open image (macOS)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            print_status "Opening image..."
            open "$OUTPUT_FILE" 2>/dev/null || echo "Could not open image automatically"
        fi
        
    else
        print_error "Failed to decode image data"
        rm /tmp/result_${TIMESTAMP}.json
        exit 1
    fi
    
elif aws s3 ls "$FAILURE_LOCATION" &>/dev/null; then
    # Check for failure
    print_error "Inference failed!"
    print_status "Downloading failure details..."
    aws s3 cp "$FAILURE_LOCATION" /tmp/failure_${TIMESTAMP}.json --quiet
    
    print_error "Failure details:"
    cat /tmp/failure_${TIMESTAMP}.json | jq '.' || cat /tmp/failure_${TIMESTAMP}.json
    rm /tmp/failure_${TIMESTAMP}.json
    exit 1
    
else
    print_error "Output not ready yet. You can check manually:"
    print_status "Output: $OUTPUT_LOCATION" 
    print_status "Failure: $FAILURE_LOCATION"
    print_status "Try running this to check status:"
    echo "  aws s3 ls $OUTPUT_LOCATION"
    exit 1
fi

# Cleanup: Remove input file from S3
print_status "Cleaning up input file..."
aws s3 rm "$INPUT_S3_URI" --quiet 2>/dev/null || echo "Could not clean up input file"

print_success "All done! 🎨"