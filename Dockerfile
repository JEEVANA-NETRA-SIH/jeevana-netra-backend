# syntax=docker/dockerfile:1
#
# Jeevana Netra backend — MATLAB Runtime + compiled MATLAB service + FastAPI bridge
#
# Required build context (repository root):
#   ./bridge/                  FastAPI HTTP bridge
#   ./matlab_service/          COMPILED LINUX MATLAB SERVICE — see DEPLOYMENT.md
#                              Generated on Linux MATLAB (REQUIRED, see below)
#                              with:
#                                mcc -m matlab_backend/run_jeevana_service.m ... -a *.mat
#                              then the output folder copied to ./matlab_service.
#   (matlab_backend/*.mat are intentionally excluded: they are bundled inside
#    the compiled MATLAB archive/CTF via mcc -a and must NOT be copied again.)
#
# CRITICAL: The MATLAB service MUST be compiled on Linux. MATLAB Compiler does
# NOT cross-compile (mcc only targets the host OS). The Windows
# `jeevana_netra_service.exe` from this repo's Windows dev build CANNOT run in
# this Linux container — never copy it into ./matlab_service.
#
# Base image: official MathWorks MATLAB Runtime container (Linux, Ubuntu),
# public registry `containers.mathworks.com` — no auth required to pull.
#   docker pull containers.mathworks.com/matlab-runtime:r2026a
# Use the release matching the Linux compile (R2026a).
#
# Build:
#   docker build \
#     --build-arg MATLAB_RUNTIME_IMAGE=containers.mathworks.com/matlab-runtime:r2026a \
#     --build-arg MATLAB_SERVICE_DIR=./matlab_service \
#     -t jeevana-netra-backend .
ARG MATLAB_RUNTIME_IMAGE=containers.mathworks.com/matlab-runtime:r2026a

FROM ${MATLAB_RUNTIME_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV HOME=/tmp/matlab_home

# Agree to the MATLAB Runtime license inside the container (required by the
# official MathWorks MATLAB Runtime image) and pin LD_LIBRARY_PATH to the
# Runtime install path (`/opt/matlabruntime/R2026a` inside the official image)
# so the compiled binary finds the MCR regardless of image defaults.
ENV AGREE_TO_MATLAB_RUNTIME_LICENSE=yes
ENV LD_LIBRARY_PATH="/opt/matlabruntime/R2026a/runtime/glnxa64:/opt/matlabruntime/R2026a/bin/glnxa64:/opt/matlabruntime/R2026a/sys/os/glnxa64:/opt/matlabruntime/R2026a/sys/opengl/lib/glnxa64:/opt/matlabruntime/R2026a/extern/bin/glnxa64"

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

# Compiled LINUX MATLAB service (mcc -m output: the `jeevana_netra_service`
# Linux binary + CTF bundle). We point JEEVANA_NETRA_EXE at the BINARY, NOT
# `run_jeevana_service.sh`: that launcher bakes in the compile-machine's full
# MATLAB install path (e.g. /opt/matlab/R2026a), which does not exist in the
# Runtime container. The Runtime container (with LD_LIBRARY_PATH set above)
# is what the binary needs to find MCR.
ARG MATLAB_SERVICE_DIR=./matlab_service
COPY ${MATLAB_SERVICE_DIR}/ /app/matlab_service/

# Writable runtime directories (MCR cache + SQLite persistence).
RUN mkdir -p /tmp/matlab_home /app/data /app/matlab_prefdir \
    && chmod -R 0777 /app/data /tmp/matlab_home /app/matlab_prefdir

ENV MATLAB_DEPLOY_MODE=cli
ENV JEEVANA_NETRA_EXE=/app/matlab_service/jeevana_netra_service
ENV JEEVANA_NETRA_DB=/app/data/jeevana_netra.db
ENV MATLAB_PREFDIR=/app/matlab_prefdir
ENV TMP_DIR=/tmp

EXPOSE 8000

CMD ["sh", "-c", "/opt/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]