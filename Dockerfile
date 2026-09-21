# syntax=docker/dockerfile:1
#
# Jeevana Netra backend — MATLAB Runtime + compiled MATLAB service + FastAPI bridge
#
# Required build context (repository root):
#   ./bridge/                  FastAPI HTTP bridge
#   ./matlab_service/          COMPILED MATLAB SERVICE — see DEPLOYMENT.md
#                              Generated on a MATLAB machine with:
#                              mcc -m matlab_backend/run_jeevana_service.m ... -a *.mat
#   (matlab_backend/*.mat are intentionally excluded: they are bundled inside
#    the compiled MATLAB archive/CTF via mcc -a and must NOT be copied again.)
#
# Build:
#   docker build \
#     --build-arg MATLAB_RUNTIME_IMAGE=mathworks/matlab-runtime:R2025b \
#     --build-arg MATLAB_SERVICE_DIR=./matlab_service \
#     -t jeevana-netra-backend .
#
# The default MATLAB_RUNTIME_IMAGE tag MUST be confirmed against the MATLAB
# release used on the compilation machine (see DEPLOYMENT.md). The saved
# networks (created Sep 2026) require a Runtime at least as new.
ARG MATLAB_RUNTIME_IMAGE=mathworks/matlab-runtime:R2025b

FROM ${MATLAB_RUNTIME_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV HOME=/tmp/matlab_home

# Python runtime for the FastAPI bridge (runtime images may not ship Python).
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv $VIRTUAL_ENV

WORKDIR /app/bridge

COPY bridge/ /app/bridge/
RUN /opt/venv/bin/pip install --no-cache-dir \
        --upgrade pip \
        -r /app/bridge/requirements.txt

# Compiled MATLAB service (mcc -m output: run_jeevana_service.sh + binary).
ARG MATLAB_SERVICE_DIR=./matlab_service
COPY ${MATLAB_SERVICE_DIR}/ /app/matlab_service/

# Writable runtime directories (MCR cache + SQLite persistence).
RUN mkdir -p /tmp/matlab_home /app/data /app/matlab_prefdir \
    && chmod -R 0777 /app/data /tmp/matlab_home /app/matlab_prefdir

ENV MATLAB_DEPLOY_MODE=cli
ENV JEEVANA_NETRA_EXE=/app/matlab_service/run_jeevana_service.sh
ENV JEEVANA_NETRA_DB=/app/data/jeevana_netra.db
ENV MATLAB_PREFDIR=/app/matlab_prefdir
ENV TMP_DIR=/tmp

EXPOSE 8000

CMD ["sh", "-c", "/opt/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]