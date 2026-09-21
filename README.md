# Jeevana Netra MATLAB Backend

MATLAB-based backend for the **Jeevana Netra** diabetic retinopathy screening system.

The backend provides AI-based retinal image analysis, diabetic retinopathy classification, image-quality assessment, confidence estimation, referral status, and explainable lesion evidence.

## Project

**Project:** Jeevana Netra  
**Purpose:** Explainable AI for Diabetic Retinopathy Screening  
**Technology:** MATLAB  
**Deployment:** MATLAB Compiler / MATLAB Runtime / Docker

## Backend Structure

```text
matlab_backend/
│
├── jeevana_netra_api.m
├── jeevana_netra_predict.m
├── preprocess_retinal_image.m
├── prepare_jeevana_model_input.m
├── extract_lesion_evidence.m
├── summarize_lesion_evidence.m
│
├── jeevana_patient_api.m
├── jeevana_report_api.m
│
├── ResNet101_APTOS_Final_Trained.mat
├── IDRiD_Lesion_Evidence_ResNet101.mat
└── IDRiD_Lesion_Evidence_Thresholds.mat
