# StableDiffusion deployment on Sagemaker

A Python FastAPI that hosts a [SD-turbo](https://huggingface.co/stabilityai/sd-turbo) /predict endpoint for local development and /invocation endpoint for hosting with AWS SagemakerAI.

The /infra dir uses Terraform to manage the deployment of an [aws_sagemaker_model](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_model), [aws_sagemaker_endpoint_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_endpoint_configuration) and [aws_sagemaker_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sagemaker_endpoint).

These terraform resources orchestrate the deployment of an asynchronous Sagemaker endpoint that can be used to serve requests. 

Data transfer is done within the VPC itself using VPC endpoints to ensure data transfer costs are kept low. There is no need for NAT gateway/interfaces to be used for this project.

{TODO: Need to include information on how this endpoint is queried}

## Architecture

![Architecture Diagram](images/architecture.drawio.png)

Application auto-scaling has been implemented to ensure the endpoint scales to zero when not in use to keep costs low. 

Terraform also provides an execution role for Sagemaker (least privilege) to allow Sagemaker to pull the model artefacts stored in S3.

MacOS was used for local development and model deployment.

# Key Information

Cost per day for the solution: 
Cloud: AWS.
Authentication: IAM roles with least priviledge applied.
Network: VPC (model in private subnets with VPC Interface and Gateway Endpoints used for routing traffic through the VPC Route layer/AWS backbone).
Model layer: Sagemaker AI [ml.g4dn.2xlarge] & stable diffusion xl turbo for production use.
Data layer: S3 is used for terraform state and model storage and output. DynamoDB is used for the terraform state lock.

# Project management

I switched the requirements.txt to a pyproject.toml and installed Astral’s UV to ensure that dependency management is ready from the first step.

# Optimisation of model code

Initially, downloading the artefacts and running inference = ⏱  817.230s (13 mins)

Removing the torch.cuda.synchronize()

This slows down the application because it forces the CPU to block.

Diffusers handles GPU compute internally and automatically synchronises where necessary.

Typical SDXL code has zero manual synchronisations.

## Model loader module

The model_loader configures the PyTorch pipeline depending on the environment. Development on MacOS requires running the model entirely on the cpu. Deployment on an ml.g4dn.2xlarge instance can make use of the GPU.

The model_loader module is working and reduces the processing time to ⏱  74.648s when running locally.

## Model warm-up

After adding a model warmup to the inference code, image generation time is now coming in at 14.399s when testing locally.

# Containerise the model

* Use a smaller base image to improve build times.
* Modified layers to increase usage of cache.

# Github Actions

* Create AWS ECR for Image to be pushed to. Each image is tagged using the commit's shasum so that they can all be uniquely identified and mapped to a commit.
* Create identity provider for OIDC with GitHub to allow GitHub to push images to ecr
* Create role for Github to use
* Attach restrictive policy
* Add a GitHub actions yaml definition to build docker image and push to ecr when new pushes to main branch

Two jobs are defined in the /.github. Environment variables are used to set sensitive values (although not secret values):

* *build-and-push.yml*: build docker image and push to AWS ECR
* *deploy-infrastructure.yml*: run terraform plan and apply jobs. The apply job required manual triggering to allow a human to review the plan before it is applied.

# Deployment on Sagemaker

TODO section

# Useful commands

## Project management

Create a pyproject.toml: `uv init --bare`

Import everything from requirements.txt: `uv add -r requirements.txt`

Add a new dependency: `uv add <dependency>`

Remove a dependency: `uv remove <dependency>`

Sync environment: `uv sync`

Run the app/test:  `uv run python src/app.py`

## Build image and test /predict endpoint locally

To run the /predict API: 

`uv run uvicorn src.inference_handler:app --reload --port 8000`

Then on a different terminal, to query the endpoint:

`curl -s -X POST http://127.0.0.1:8000/predict -H "Content-Type: application/json" -d '{"prompt": "a cat astronaut on the moon"}' | jq -r '.image' | base64 --decode > output-cat.png`


## Deploy image in AWS

TODO

## Using the endpoint

TODO