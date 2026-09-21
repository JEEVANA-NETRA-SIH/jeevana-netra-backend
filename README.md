# Jeevana Netra MATLAB Backend

MATLAB + HTTP bridge backend for the **Jeevana Netra** AI-based diabetic
retinopathy screening system.

The backend provides AI-based retinal image analysis, diabetic retinopathy
classification, image-quality assessment, confidence estimation, referral
status, and explainable lesion evidence — plus a real HTTP API to consume
them.

## Project

**Project:** Jeevana Netra  
**Purpose:** Explainable AI for Diabetic Retinopathy Screening  
**Frontend:** https://jeevananetra.vercel.app<br>
**Backend API docs:** [`API.md`](API.md)<br>
**Deployment guide:** [`DEPLOYMENT.md`](DEPLOYMENT.md)

---

## Backend Structure

```text
├── matlab_backend/                 MATLAB AI pipeline (source)
│   ├── jeevana_netra_api.m         Orchestrator (image bytes -> screening result)
│   ├── jeevana_netra_predict.m     ResNet-101 DR classification + referral logic
│   ├── preprocess_retinal_image.m  Quality check + CLAHE enhancement
│   ├── prepare_jeevana_model_input.m
│   ├── extract_lesion_evidence.m   Patch Grad-CAM lesion evidence
│   ├── summarize_lesion_evidence.m Heatmap -> compact regions
│   ├── jeevana_report_api.m        Two-page AI screening PDF
│   ├── jeevana_netra_json_api.m    JSON-contract wrapper (bridge -> MATLAB)
│   ├── jeevana_report_json_api.m   JSON-contract wrapper (bridge -> MATLAB)
│   ├── run_jeevana_service.m       Standalone CLI entry for mcc compilation
│   ├── jeevana_patient_api.m       (SQLite patient API - Database Toolbox, kept
│   │                                for reference; persistence moved to bridge)
│   ├── ResNet101_APTOS_Final_Trained.mat        (Git LFS, ~159 MB)
│   ├── IDRiD_Lesion_Evidence_ResNet101.mat      (Git LFS, ~159 MB)
│   └── IDRiD_Lesion_Evidence_Thresholds.mat
├── bridge/                         FastAPI HTTP bridge (deployable)
│   ├── app/                        Router, schemas, SQLAlchemy persistence,
│   │                               MATLAB service adapters (cli / sdk)
│   ├── tests/                      pytest suite
│   └── requirements.txt
├── Dockerfile                      MATLAB Runtime + bridge container
├── API.md                          HTTP API contract
├── DEPLOYMENT.md                   Render + MATLAB Compiler build steps
└── matlab_service/                 (generated) compiled MATLAB artifact - see
                                    DEPLOYMENT.md, git-ignored
```

## Architecture

```
Vercel Frontend ──HTTPS──► FastAPI bridge ──JSON──► compiled MATLAB (MCR)
                                              │
                                              ├─ screen -> DR class + Grad-CAM
                                              └─ report -> PDF
                                              SQLite/PostgreSQL (bridge-owned)
```

The MATLAB code contains the real diabetic retinopathy processing logic and is
**not reimplemented or faked** by the bridge. The bridge only handles HTTP,
validation and persistence.

## API Endpoints

| Method | Endpoint | Purpose |
| ------ | -------- | ------- |
| GET | `/health` | Liveness + MATLAB status |
| POST | `/api/screen` | Analyze a retinal image (multipart) |
| POST | `/api/screenings` | Save a real screening result |
| GET | `/api/screenings` | Screening history |
| GET | `/api/patients` | Patient records |
| GET | `/api/patients/{id}` | Patient screening history |
| POST | `/api/report` | Generate the AI screening PDF |

Full request/response documentation: [`API.md`](API.md).

## Running the bridge locally (no MATLAB needed)

```bash
cd bridge
python -m venv .venv && .venv/Scripts/activate     # Windows
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
```

Without a compiled MATLAB artifact the screening/report endpoints correctly
answer `503 "MATLAB screening service is not configured."` — the project does
not ship mock AI predictions.

## Tests

```bash
cd bridge
pytest
```

Tests covering real-model inference are skipped unless a compiled MATLAB
artifact and a real retinal test image are configured (`JEEVANA_NETRA_TEST_IMAGE`,
`JEEVANA_NETRA_EXE` / `JEEVANA_NETRA_SDK_PACKAGE`) — see
`bridge/tests/test_matlab_required.py`.

## Deployment

See [`DEPLOYMENT.md`](DEPLOYMENT.md): MATLAB Compiler build steps, Docker
build, Render Web Service configuration, environment variables, persistence
and resource requirements.

## Disclaimer

AI-assisted prototype. Not a substitute for professional medical diagnosis or
treatment. Clinical findings should be reviewed by a qualified clinician.