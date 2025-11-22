# src/app.py
from pathlib import Path
from src.model_loader import get_pipeline


def generate_image(prompt: str, output_path: str = "output.png"):
    pipe = get_pipeline()   # <- shared loader

    print("Generating image...")
    result = pipe(prompt, num_inference_steps=8, guidance_scale=0.0)

    image = result.images[0].convert("RGB")

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)
    print(f"Saved to {output_path}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", type=str, required=True)
    args = parser.parse_args()

    generate_image(args.prompt)