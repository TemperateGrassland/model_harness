# sd-turbo deployment with Asynchronous SagemakerAI Endpoint

A Python FastAPI that hosts a [SD-turbo](https://huggingface.co/stabilityai/sd-turbo) /predict endpoint for local development and /invocation endpoint for hosting with AWS SagemakerAI. The /invocation endpoint hosted in Sagemaker is asynchronous and currently requires manual triggering via the cli. The model reads from an S3 bucket, processes the prompt and stores the output in the same S3 bucket. 

The /infra dir uses Terraform to manage the deployment of an [aws_sagemaker_model](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_model), [aws_sagemaker_endpoint_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_endpoint_configuration) and [aws_sagemaker_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_endpoint).

## Architecture

![Architecture Diagram](images/architecture.drawio.png)

Application auto-scaling has been implemented to ensure the endpoint scales to zero when not in use to keep costs low. 

Data transfer uses VPC endpoints to ensure data transfer costs are kept low.

# Github Actions

Two jobs are defined in the /.github:

* *build-and-push.yml*: build docker image and push to AWS ECR. Each image is tagged using the commit's shasum so that they can all be uniquely identified and mapped to a commit.
* *deploy-infrastructure.yml*: run terraform plan and apply jobs. The apply job required manual triggering to allow a human to review the plan before it is applied.

# Deployment on Sagemaker

sd-turbo is deployed as a synchronous and asynchronous model endpoint. Model querying happens via an aws cli call to the endpoint. 

For the async endpoint, input is read from S3 and outputs and failures are saved to `s3://model-harness-io/outputs/` and `s3://model-harness-io/failures/` respectively.

The sync endpoint can be used to query the model and return the response directly for further processing. 

# Useful commands

## Build image and test /predict endpoint locally

To run the /predict API: 

`uv run uvicorn src.inference_handler:app --reload --port 8000`

Open a new terminal to query the endpoint:

`curl -s -X POST http://127.0.0.1:8000/predict -H "Content-Type: application/json" -d '{"prompt": "a cat astronaut on the moon"}' | jq -r '.image' | base64 --decode > output-cat.png`

## Using the async endpoint

Requires AWS credentials. 

Run the bash script at /script/image_url.sh for an interactive way to prompt the model and view the output. Alternatively, key commands are available below:

### create query

`echo '{"prompt": "a futuristic cat floating in the clouds"}' > input.json`

`aws s3 cp input.json s3://model-harness-io/input.json`

### query model

Make a note of the `OutputLocation` in the response, it will be needed next:

```
aws sagemaker-runtime invoke-endpoint-async \
      --endpoint-name "model-harness-endpoint" \
      --input-location "s3://model-harness-io/input.json" \
      --content-type "application/json"
```

### download image

aws s3 cp "<OUTPUT_LOCATION>" result.json

### open image

`cat result.json | jq -r '.image' | base64 -d > generated_image.png`

`open generated_image.png`

![alt text](scripts/generated_image.png)

## Using the sync endpoint

Use the command below and update the prompt field to query the endpoint, decode the result and open the generated image:

```
aws sagemaker-runtime invoke-endpoint \
  --region eu-west-1 \
  --endpoint-name model-harness-sync-endpoint \
  --body '{"prompt": "Hello from CLI"}' \
  --content-type application/json \
  --cli-binary-format raw-in-base64-out \
  result.json && \
jq -r '.image' result.json | base64 --decode > output.png && \
open output.png
```

## Facts
* local Docker image build (no-caching): 4.5 mins
* Local Docker image build and push to ecr: 6.5 mins
* sdxl-turbo model artefacts tarball: 9GB