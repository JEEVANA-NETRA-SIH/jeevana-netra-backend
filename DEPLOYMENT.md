# Jeevana Netra Backend — Deployment Guide

Deployable target: **Render Web Service (Docker)** behind
`https://jeevananetra.vercel.app`.

This document is honest about what is automated today and what still requires
a MATLAB build machine. **No part of the MATLAB processing logic is faked in
deployment:** if the compiled MATLAB component is missing, the API answers
`503 "MATLAB screening service is not configured."`

---

## Architecture

```
Vercel Frontend (https://jeevananetra.vercel.app)
        │ HTTPS
        ▼
Render Web Service (Docker)
  FastAPI bridge  ──►  compiled MATLAB service (MCR)
                          │
                          ├─ job: screen        → ResNet-101 DR classification + Grad-CAM evidence
                          └─ job: generate_report → 2-page PDF
  SQLite / PostgreSQL (owned by the bridge)
```

The bridge:

- speaks HTTP/JSON/multipart,
- validates and size-limits uploads,
- encodes image bytes as base64 and forwards a JSON contract to MATLAB
  (`matlab_backend/jeevana_netra_json_api.m`, `jeevana_report_json_api.m`)
- stores patients/screenings in SQLite (SQLAlchemy; swap to PostgreSQL by
  setting `DATABASE_URL`),
- never fabricates AI output.

---

## How the bridge calls MATLAB

Two production backends implement the same `MatlabScreeningService` adapter:

| Mode (`MATLAB_DEPLOY_MODE`) | Artifact | Entry |
| --------------------------- | -------- | ----- |
| `cli` | MATLAB Compiler standalone executable | `JEEVANA_NETRA_EXE` → `run_jeevana_service.sh <req.json> <resp.json>` |
| `sdk` | MATLAB Compiler SDK Python package | `JEEVANA_NETRA_SDK_PACKAGE` (`jeevana_netra_json_api`, `jeevana_report_json_api`) |

Both exchange **JSON strings only**; no MATLAB type marshalling occurs in
Python. Development default (`none`) returns HTTP 503.

---

## Step 1 — Build the compiled MATLAB component (REQUIRED, on a MATLAB machine)

Requires a MATLAB license with:

- MATLAB Compiler
- Deep Learning Toolbox
- Image Processing Toolbox

**The compilation MATLAB release must be at least as new as the release that
saved the networks** (`.mat` headers show creation `Sun Sep 13 2026` /
`Sun Sep 20 2026`). Using an old runtime will fail to `load()` the network
objects. Expected family: **R2025b / R2026a** — verify by running the load on
the build machine first.

Compile the JSON-contract service (CLI mode — recommended):

```matlab
cd matlab_backend
mcc -m run_jeevana_service.m \
    jeevana_netra_api.m jeevana_netra_predict.m \
    preprocess_retinal_image.m prepare_jeevana_model_input.m \
    extract_lesion_evidence.m summarize_lesion_evidence.m \
    jeevana_report_api.m jeevana_report_json_api.m jeevana_netra_json_api.m \
    -a ResNet101_APTOS_Final_Trained.mat \
    -a IDRiD_Lesion_Evidence_ResNet101.mat \
    -a IDRiD_Lesion_Evidence_Thresholds.mat \
    -o jeevana_netra_service
```

This produces `jeevana_netra_service/` with `run_jeevana_service.sh`
(launcher) plus binary and CTF. **Copy the whole folder into the repository
root as `matlab_service/`** (it is git-ignored, so it must be produced by the
build/CI pipeline or copied manually before `docker build`).

For SDK mode instead: use MATLAB Compiler → **Library Compiler** →
**Python Package** exporting `jeevana_netra_json_api` and
`jeevana_report_json_api`, then set `JEEVANA_NETRA_SDK_PACKAGE`.

> Note: `jeevana_patient_api.m` (Database Toolbox) is deliberately NOT
> compiled — Database Toolbox cannot be packaged with MATLAB Compiler.
> Persistence moved to the bridge.

---

## Step 2 — Local run (bridge only, no MATLAB needed)

```bash
cd bridge
python -m venv .venv
.venv\Scripts\activate          # Windows
# .venv/bin/activate            # Linux/macOS
pip install -r requirements-dev.txt
set JEEVANA_NETRA_DB=.\data\jeevana_netra.db
set CORS_ORIGINS=https://jeevananetra.vercel.app,http://localhost:5173
uvicorn app.main:app --reload --port 8000
```

- `GET /health` → `{"status":"ok", ...}`
- `POST /api/screen` or `POST /api/report` → **HTTP 503 "MATLAB screening
  service is not configured."** until the compiled artifact is wired in.
  This is intentional: no fake predictions.
- Interactive docs: `http://localhost:8000/docs`

---

## Step 3 — Docker build

```bash
# Populate ./matlab_service with the mcc output first (Step 1).
docker build \
  --build-arg MATLAB_RUNTIME_IMAGE=mathworks/matlab-runtime:R2025b \
  --build-arg MATLAB_SERVICE_DIR=./matlab_service \
  -t jeevana-netra-backend .

docker run --env-file bridge/.env.example -p 8000:8000 jeevana-netra-backend
```

**About `MATLAB_RUNTIME_IMAGE`:** MathWorks publishes MATLAB Runtime images
on Docker Hub (`mathworks/matlab-runtime`). Your `mcc -m` build emits a
`LDF`/launcher tied to the Runtime of the exact release used to compile —
**choose the tag matching your build-machine MATLAB release** (do not guess
R2020b/R2021a/R2022b; the Sep-2026 networks need a current runtime). Verify
the exact tag on the MathWorks Docker Hub page for your release.

---

## Step 4 — Render deployment

### Render service type

**Docker Web Service** pointing at the repository root (uses the `Dockerfile`).

### Required environment variables

| Variable | Value |
| -------- | ----- |
| `PORT` | Set by Render automatically (the app binds `0.0.0.0:$PORT`). |
| `MATLAB_DEPLOY_MODE` | `cli` |
| `JEEVANA_NETRA_EXE` | `/app/matlab_service/run_jeevana_service.sh` |
| `JEEVANA_NETRA_DB` | `/app/data/jeevana_netra.db` |
| `MATLAB_PREFDIR` | `/app/matlab_prefdir` (writable MCR cache dir; created by the image) |
| `CORS_ORIGINS` | `https://jeevananetra.vercel.app` |
| `JEEVANA_API_KEY` | _optional_ — set a shared key to protect all `/api/*` routes |
| `MAX_UPLOAD_MB` | `20` (match the frontend's 20 MB cap) |

No secret values are assumed; nothing is committed to the repository.

### Persistent storage

SQLite writes to `JEEVANA_NETRA_DB`. Render's container filesystem is
**ephemeral** — the database is wiped on redeploys/restarts unless a
**Render Disk** (paid add-on) is mounted and `JEEVANA_NETRA_DB` points into it
(e.g. `/data/jeevana_netra.db` on the mounted disk). For production,
PostgreSQL is preferred: set `DATABASE_URL` and add the `psycopg`/pg driver to
`requirements.txt` — the repository layer is engine-agnostic.

### RAM & CPU

ResNet-101 inference + Grad-CAM run on **CPU**, loading ~318 MB of model
weights, plus MATLAB Runtime memory and the Python bridge. This realistically
needs **≥ 2 GB RAM** (more for concurrent requests). Render Free/Starter
(512 MB) is not sufficient. Do **not** assume a specific plan works — start
with ≥ 2 GB, run real test images, and scale up based on observed memory.

### Health endpoint

`GET /health` (no auth) — use it as the Render health check path. It reports
`"status":"ok"` and the honest MATLAB state
(`unavailable` / `configured` / `initialized`).

### Startup command

`sh -c "/opt/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"`

(The `CMD` in the `Dockerfile` already does this; Render only needs the port.)

### Cold start

MATLAB Runtime initialization is slow. Expect the first request to take tens
of seconds and increase Render's start/health-check grace period. The model is
loaded once per compiled process (`persistent netFinal`). Run a single worker.

---

## Git LFS

`ResNet101_APTOS_Final_Trained.mat` and `IDRiD_Lesion_Evidence_ResNet101.mat`
are Git LFS objects (~159 MB each). They are bundled into the compiled MATLAB
archive by `mcc -a`, so the Docker build context does not need the raw `.mat`
files (they are excluded via `.dockerignore`). If the container must instead
load the models standalone, install `git-lfs` in the builder image and run
`git lfs pull` before `docker build` so the real files (not pointers) reach
the context.

---

## Frontend contract

The Vercel frontend will call (integration done separately):

```text
VITE_API_BASE_URL=https://<render-service>.onrender.com
```

Mapped endpoints (see `API.md` for full schemas):

| Frontend need | Endpoint |
| ------------- | -------- |
| Upload + analyze image | `POST {VITE_API_BASE_URL}/api/screen` |
| Save screening result | `POST {VITE_API_BASE_URL}/api/screenings` |
| Screening history | `GET {VITE_API_BASE_URL}/api/screenings` |
| Patient records | `GET {VITE_API_BASE_URL}/api/patients` |
| One patient history | `GET {VITE_API_BASE_URL}/api/patients/{id}` |
| PDF report | `POST {VITE_API_BASE_URL}/api/report` |
| Health | `GET {VITE_API_BASE_URL}/health` |

CORS allows `https://jeevananetra.vercel.app` (and localhost dev origins).

---

## Remaining blockers (require a MATLAB build machine / licenses)

1. **MATLAB Compiler license + installation** with Deep Learning Toolbox and
   Image Processing Toolbox → run `mcc -m` (Step 1).
2. **Exact MATLAB / Runtime release** confirmation — must match or exceed the
   Sep 2026 model save release; verify `load()` of both networks on the build
   machine.
3. **Grad-CAM/`extractdata` under Runtime** — verify the compiled
   `screen` job successfully runs the explainability path once under MCR.
4. **`MATLAB_RUNTIME_IMAGE` Docker tag** — confirm the exact MathWorks image
   tag for the chosen release.
5. **Render plan/RAM** — validate with real images; upgrade from the observed
   memory usage, not a guess.
6. **`matlab_service/` build artifact** must exist before `docker build`
   (automate with a build/CI job on the MATLAB machine if desired).