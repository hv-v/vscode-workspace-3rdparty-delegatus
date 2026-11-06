# syntax=docker/dockerfile:1.7
#
# jo-confluence-kb — the search half of .atlassian/kb/kb.py: an embedding model plus the
# libraries to run it. docker-compose.yml here runs it with --network none, a
# read-only root and the host user's id, and mounts .atlassian/kb/kb.py read-only,
# so the code stays one copy in the workspace. ../wiki/ has its own copy.
# Network is used here, at build time only.
#
# The model, multilingual-e5-small (ONNX, int8-quantised), is pinned to a
# commit of its repository and to the SHA-256 of each file.

FROM python:3.12.7-slim-bookworm

ARG MODEL_REPO=https://huggingface.co/Xenova/multilingual-e5-small/resolve
ARG MODEL_REV=761b726dd34fb83930e26aab4e9ac3899aa1fa78

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    KB_MODEL_DIR=/model \
    HOME=/tmp

RUN pip install \
        numpy==2.1.3 \
        onnxruntime==1.20.1 \
        tokenizers==0.21.0 \
        sqlite-vec==0.1.9   # 0.1.6 ships a 32-bit .so in its arm64 wheel

ADD --checksum=sha256:f80102d3f2a1229f387d3c81909990d8945513e347b0eab049f7de3c6f98c193 \
    ${MODEL_REPO}/${MODEL_REV}/onnx/model_quantized.onnx /model/model.onnx
ADD --checksum=sha256:0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39 \
    ${MODEL_REPO}/${MODEL_REV}/tokenizer.json /model/tokenizer.json
# Files fetched by ADD arrive mode 600; the container runs as the host user.
RUN chmod 755 /model && chmod 644 /model/*

WORKDIR /app
ENTRYPOINT ["python3", "/app/kb.py"]
