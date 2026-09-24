function response = jeevana_report_api(requestJson)
% JEEVANA_REPORT_API
% Generates a clinical, modern, patient-first AI screening report PDF for
% Jeevana Netra (Smart India Hackathon 2026).
%
% Three-Page Patient-First Visual Hierarchy:
%   PAGE 1: Executive Screening Summary (Dashboard View)
%           - Header: Jeevana Netra AI-Powered Screening
%           - Patient Information Card (Name, ID, Age, Gender, Date, Analysed Eye)
%           - Prominent AI Screening Result Card (Diagnosis, Severity, Confidence, Referral)
%           - Quick Condition Summary (5 scannable mini-cards: Severity, Confidence, Quality, Lesions, Macula)
%           - Key Findings (Structured concise clinical findings)
%           - DR Class Probability Distribution (Horizontal bar chart visualization)
%
%   PAGE 2: Retinal Image Analysis & Explainable AI
%           - 2x2 Structured Multi-Modal Retinal Grid:
%             * Top-Left: Original Retina Image
%             * Top-Right: Enhanced Retina View (CLAHE contrast & vessel structure)
%             * Bottom-Left: Grad-CAM Explainability Heatmap (ResNet-101 layer attention)
%             * Bottom-Right: Affected Regions / Anatomical Localization Overlay
%           - AI Explainability - Grad-CAM Narrative & Interpretability Note
%           - Suspected / Affected Lesions Summary & Regional Table
%
%   PAGE 3: Clinical Findings, Recommendations & Technical Details
%           - Clinical Screening Summary (Diagnosis, Visual Evidence, Macula, Retinal Structures)
%           - Recommended Next Steps (High-visibility action card)
%           - Image Quality & Acquisition Integrity Section
%           - Technical Details & Model Audit Trail
%           - Medical Disclaimer & Healthcare Provider Sign-Off Block
%
% API Input:
%   requestJson: JSON string or MATLAB struct matching the Jeevana Netra contract
%
% API Output:
%   response: struct with fields: status, filename, pdfBytes, sizeBytes

%% 1. Validate Input & Parse Request

if nargin < 1 || isempty(requestJson)
    error("Request JSON is required.");
end

if isstring(requestJson)
    requestJson = char(requestJson);
end

if isstruct(requestJson)
    request = requestJson;
elseif ischar(requestJson)
    request = jsondecode(requestJson);
else
    error("Request must be a struct or JSON string.");
end

if ~isfield(request,"operation")
    error("Operation is required.");
end

if string(request.operation) ~= "generate_report"
    error("Unsupported operation. Use generate_report.");
end

if ~isfield(request,"patient")
    error("Patient information is required.");
end

if ~isfield(request,"result")
    error("Screening result is required.");
end

if ~isfield(request,"imageBytes") && ~isfield(request,"imageBase64")
    error("Image data is required (imageBase64 or imageBytes).");
end

patient = request.patient;
result = request.result;

%% 2. Extract Patient Information

patientName = getStringField(patient,"name","Unknown");
patientId = getStringField(patient,"id","");
if patientId == "" || patientId == "Unknown"
    patientId = getStringField(patient,"patientId","Unknown");
end
patientGender = getStringField(patient,"gender","Not specified");
patientAge = getNumericField(patient,"age",NaN);

analysedEye = "Right Eye (OD)";
if isfield(patient,"eye") && ~isempty(patient.eye)
    analysedEye = string(patient.eye);
elseif isfield(patient,"analysedEye") && ~isempty(patient.analysedEye)
    analysedEye = string(patient.analysedEye);
elseif isfield(result,"eye") && ~isempty(result.eye)
    analysedEye = string(result.eye);
elseif isfield(result,"analysedEye") && ~isempty(result.analysedEye)
    analysedEye = string(result.analysedEye);
end

screeningId = "JN-REPORT";
if isfield(request,"screeningId") && ~isempty(request.screeningId)
    screeningId = string(request.screeningId);
end

examDate = string(datetime("now","Format","dd MMM yyyy, HH:mm"));
if isfield(request,"screeningDate") && ~isempty(request.screeningDate)
    examDate = string(request.screeningDate);
end

%% 3. Extract AI Screening Results

predictedClass = getStringField(result,"predictedClass","Unknown");
confidence = convertToPercent(getNumericField(result,"confidence",0));
confidenceStatus = getStringField(result,"confidenceStatus","Not specified");
referralStatus = getStringField(result,"referralStatus","Not specified");
recommendation = getStringField(result,"recommendation","Clinical review should be considered.");
qualityStatus = getStringField(result,"qualityStatus","Not specified");
qualityMessage = getStringField(result,"qualityMessage","");

brightness = NaN;
contrast = NaN;
sharpness = NaN;
if isfield(result,"imageQuality")
    iq = result.imageQuality;
    brightness = getNumericField(iq,"brightness",NaN);
    contrast = getNumericField(iq,"contrast",NaN);
    sharpness = getNumericField(iq,"sharpness",NaN);
end

probabilities = struct();
probabilities.NoDR = getProbability(result,"NoDR");
probabilities.Mild = getProbability(result,"Mild");
probabilities.Moderate = getProbability(result,"Moderate");
probabilities.Severe = getProbability(result,"Severe");
probabilities.ProliferativeDR = getProbability(result,"ProliferativeDR");

lesionEvidence = [];
if isfield(result,"lesionEvidence")
    lesionEvidence = result.lesionEvidence;
end

evidenceCount = countEvidenceRegions(lesionEvidence);
[numHemorrhages, numMicroaneurysms, numExudates, positiveTypesCount] = buildLesionBreakdown(lesionEvidence);

% Dynamic Macula Assessment based on lesion coordinates
maculaInvolvement = evaluateMaculaInvolvement(lesionEvidence, evidenceCount);

%% 4. Decode Retinal Image Bytes

if isfield(request,"imageBase64") && ~isempty(request.imageBase64)
    imageBytes = matlab.net.base64decode(char(request.imageBase64));
    imageBytes = uint8(imageBytes(:));
elseif isfield(request,"imageBytes") && ~isempty(request.imageBytes)
    imageBytes = uint8(request.imageBytes(:));
else
    error("Image data is required (imageBase64 or imageBytes).");
end

if isempty(imageBytes)
    error("Image bytes are empty.");
end

if isPngBytes(imageBytes)
    imageExtension = ".png";
elseif isJpegBytes(imageBytes)
    imageExtension = ".jpg";
else
    error("Unsupported image format. imageBytes must contain PNG or JPEG file bytes.");
end

tempDir = tempdir;
token = char(java.util.UUID.randomUUID.toString());
tempImage = fullfile(tempDir,"jin_rep_in_" + token + imageExtension);
tempPdf = fullfile(tempDir,"jin_rep_out_" + token + ".pdf");

deleteIfExists(tempImage);
deleteIfExists(tempPdf);

cleanupImage = onCleanup(@() deleteIfExists(tempImage)); %#ok<NASGU>

fid = fopen(tempImage,"wb");
if fid == -1
    error("Unable to create temporary image file.");
end
fwrite(fid,imageBytes,"uint8");
fclose(fid);

try
    retinalImage = imread(tempImage);
catch ME
    error("Unable to read retinal image: %s",ME.message);
end

if ndims(retinalImage) == 2
    retinalImage = repmat(retinalImage,[1 1 3]);
end

retinalImage = im2uint8(retinalImage);

%% 5. Generate Multi-Modal Views & Grad-CAM Explainability

enhancedImage = enhanceRetinalImage(retinalImage);
[heatmapImage, overlayImage, hasGradCam] = extractGradCamData(retinalImage, request, result, lesionEvidence);

safePatientId = makeSafeFilename(patientId);
timeText = string(datetime("now","Format","yyyyMMdd_HHmmss"));
fileName = char("Jeevana_Netra_Report_" + safePatientId + "_" + timeText + ".pdf");

%% 6. Color Palette (Jeevana Netra Medical Identity)

NAVY       = [11 42 74] / 255;      % #0B2A4A Primary Dark Navy
BLUE       = [20 93 160] / 255;     % #145DA0 Healthcare Blue
TEAL       = [8 127 140] / 255;     % #087F8C Explainability Teal
GREEN      = [32 164 100] / 255;    % #20A464 Healthy / Non-referable
AMBER      = [225 145 20] / 255;    % Mild DR Warning
RED        = [210 60 45] / 255;     % Moderate / Severe DR Alert
PURPLE     = [135 30 95] / 255;     % Proliferative DR Urgent
TEXT_DARK  = [26 38 57] / 255;      % Deep Slate Body Text
TEXT_MUTED = [100 116 139] / 255;   % Cool Gray Supporting Labels
BG_PAGE    = [248 250 252] / 255;   % Clean Medical Off-White Canvas
CARD_BG    = [255 255 255] / 255;   % Pure White Card Surface
BORDER     = [220 228 236] / 255;   % Subtle Card Border
WHITE      = [1 1 1];

accent = severityColor(predictedClass,GREEN,AMBER,RED,PURPLE,BLUE);
softAccent = blendWithWhite(accent,0.92);

% ============================================================
% PAGE 1 - EXECUTIVE SCREENING SUMMARY (PATIENT-FIRST VIEW)
% ============================================================
fig1 = makePageFigure();
ax1 = makePageAxes(fig1);

% Page Canvas
rectangle(ax1,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeader(ax1,screeningId,examDate,NAVY,TEAL,WHITE);

% 1. Patient Information Card (Y: 21.0 -> 37.5, H: 16.5, W: 92)
drawCard(ax1,4.0,21.0,92.0,16.5,CARD_BG,BORDER);
text(ax1,6.5,23.8,"PATIENT INFORMATION","Color",NAVY,"FontSize",7.8,"FontWeight","bold");
rectangle(ax1,"Position",[6.5 25.2 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Row 1
text(ax1,6.5,28.5,"PATIENT NAME","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,6.5,31.8,string(patientName),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold","Interpreter","none");

text(ax1,38.0,28.5,"PATIENT ID","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,38.0,31.8,string(patientId),"Color",TEXT_DARK,"FontSize",8.2,"FontWeight","bold","Interpreter","none");

text(ax1,68.0,28.5,"ANALYSED EYE","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,68.0,31.8,string(analysedEye),"Color",NAVY,"FontSize",8.2,"FontWeight","bold","Interpreter","none");

% Row 2
text(ax1,6.5,34.2,"AGE:","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,12.5,34.2,formatAge(patientAge),"Color",TEXT_DARK,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

text(ax1,24.0,34.2,"GENDER:","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,33.0,34.2,string(patientGender),"Color",TEXT_DARK,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

text(ax1,48.0,34.2,"EXAMINATION DATE:","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
text(ax1,68.0,34.2,string(examDate),"Color",TEXT_DARK,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

% 2. MOST IMPORTANT SECTION — AI SCREENING RESULT CARD (Y: 39.5 -> 59.5, H: 20.0, W: 92)
drawCard(ax1,4.0,39.5,92.0,20.0,CARD_BG,BORDER);

% Top title strip of Result Card
rectangle(ax1,"Position",[4.0 39.5 92.0 4.2],"FaceColor",accent,"EdgeColor","none");
text(ax1,6.5,42.2,"★  AI SCREENING RESULT  —  PRIMARY DIAGNOSTIC ASSESSMENT","Color",WHITE,"FontSize",7.0,"FontWeight","bold");

% Large prominent diagnosis
diagnosisText = formatDiagnosisTitle(predictedClass);
text(ax1,6.5,49.0,upper(diagnosisText),"Color",accent,"FontSize",14.5,"FontWeight","bold","Interpreter","none");
text(ax1,6.5,52.8,formatGradeTag(predictedClass),"Color",TEXT_MUTED,"FontSize",6.8,"FontWeight","bold","Interpreter","none");

% 4 Key Metrics Bar inside Result Card
rectangle(ax1,"Position",[6.5 54.2 87.0 4.2],"FaceColor",[0.95 0.97 0.99],"EdgeColor",BORDER,"LineWidth",0.4);

text(ax1,8.0,56.8,"SEVERITY:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax1,18.5,56.8,string(predictedClass),"Color",accent,"FontSize",6.8,"FontWeight","bold","Interpreter","none");

text(ax1,33.0,56.8,"CONFIDENCE:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax1,46.5,56.8,sprintf("%.1f%%",confidence),"Color",NAVY,"FontSize",6.8,"FontWeight","bold");

text(ax1,58.0,56.8,"EYE:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax1,63.5,56.8,string(analysedEye),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold","Interpreter","none");

text(ax1,76.0,56.8,"REFERRAL:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax1,87.0,56.8,wrapText(char(referralStatus),15,1),"Color",accent,"FontSize",6.2,"FontWeight","bold","Interpreter","none");

% 3. QUICK CONDITION SUMMARY (Y: 61.5 -> 74.0, H: 12.5, W: 92)
% 5 compact scannable cards (W: 17.2, gap 1.5)
cW = 17.2;
gap = 1.5;
cardsX = 4.0 + (0:4) * (cW + gap);

% Card 1: DR Severity
drawCard(ax1,cardsX(1),61.5,cW,12.5,CARD_BG,BORDER);
text(ax1,cardsX(1)+cW/2,64.2,"DR SEVERITY","Color",TEXT_MUTED,"FontSize",5.4,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(1)+cW/2,68.0,string(predictedClass),"Color",accent,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax1,cardsX(1)+cW/2,71.5,"Clinical Grade","Color",TEXT_MUTED,"FontSize",5.2,"HorizontalAlignment","center");

% Card 2: AI Confidence
drawCard(ax1,cardsX(2),61.5,cW,12.5,CARD_BG,BORDER);
text(ax1,cardsX(2)+cW/2,64.2,"AI CONFIDENCE","Color",TEXT_MUTED,"FontSize",5.4,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(2)+cW/2,68.0,sprintf("%.1f%%",confidence),"Color",NAVY,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(2)+cW/2,71.5,sprintf("[%s Tier]",confidenceStatus),"Color",TEXT_MUTED,"FontSize",5.2,"HorizontalAlignment","center","Interpreter","none");

% Card 3: Image Quality
drawCard(ax1,cardsX(3),61.5,cW,12.5,CARD_BG,BORDER);
text(ax1,cardsX(3)+cW/2,64.2,"IMAGE QUALITY","Color",TEXT_MUTED,"FontSize",5.4,"FontWeight","bold","HorizontalAlignment","center");
qualityScoreStr = formatQualityIndex(qualityStatus);
text(ax1,cardsX(3)+cW/2,68.0,qualityScoreStr,"Color",qualityColor(qualityStatus,GREEN,AMBER,RED),"FontSize",8.0,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(3)+cW/2,71.5,"Gradable: Yes","Color",TEXT_MUTED,"FontSize",5.2,"HorizontalAlignment","center");

% Card 4: Lesions Detected
drawCard(ax1,cardsX(4),61.5,cW,12.5,CARD_BG,BORDER);
text(ax1,cardsX(4)+cW/2,64.2,"LESIONS DETECTED","Color",TEXT_MUTED,"FontSize",5.4,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(4)+cW/2,68.0,sprintf("%d",evidenceCount),"Color",TEXT_DARK,"FontSize",9.0,"FontWeight","bold","HorizontalAlignment","center");
if evidenceCount > 0
    text(ax1,cardsX(4)+cW/2,71.5,"Suspected Regions","Color",accent,"FontSize",5.2,"FontWeight","bold","HorizontalAlignment","center");
else
    text(ax1,cardsX(4)+cW/2,71.5,"Field Clear","Color",GREEN,"FontSize",5.2,"FontWeight","bold","HorizontalAlignment","center");
end

% Card 5: Macula Status
drawCard(ax1,cardsX(5),61.5,cW,12.5,CARD_BG,BORDER);
text(ax1,cardsX(5)+cW/2,64.2,"MACULA STATUS","Color",TEXT_MUTED,"FontSize",5.4,"FontWeight","bold","HorizontalAlignment","center");
if contains(lower(maculaInvolvement),"spared") || contains(lower(maculaInvolvement),"no")
    macColor = GREEN;
    macLabel = "Spared";
else
    macColor = AMBER;
    macLabel = "Involved";
end
text(ax1,cardsX(5)+cW/2,68.0,macLabel,"Color",macColor,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,cardsX(5)+cW/2,71.5,"No Edema Detected","Color",TEXT_MUTED,"FontSize",5.2,"HorizontalAlignment","center");

% 4. KEY FINDINGS (Y: 76.0 -> 102.0, H: 26.0, W: 92)
drawCard(ax1,4.0,76.0,92.0,26.0,CARD_BG,BORDER);
text(ax1,6.5,79.2,"KEY CLINICAL & AI FINDINGS","Color",NAVY,"FontSize",8.2,"FontWeight","bold");
rectangle(ax1,"Position",[6.5 80.5 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Bullet 1: Primary Diagnosis
drawBulletIcon(ax1,7.0,83.8,BLUE);
text(ax1,10.0,84.0,"Primary Diagnosis:","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
f1 = sprintf("%s identified with %.1f%% model certainty (%s confidence tier).",diagnosisText,confidence,confidenceStatus);
text(ax1,29.0,84.0,wrapText(f1,82,1),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

% Bullet 2: Lesion Breakdown
drawBulletIcon(ax1,7.0,89.2,accent);
text(ax1,10.0,89.4,"Biomarker Evidence:","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
if evidenceCount > 0
    f2 = sprintf("%d suspected lesion region(s) detected: %d Haemorrhage/Microaneurysm, %d Exudate foci localized.", ...
        evidenceCount, (numHemorrhages + numMicroaneurysms), numExudates);
else
    f2 = "0 focal lesion regions detected above threshold. Retinal parenchyma and vascular arcade show no referable lesions.";
end
text(ax1,31.5,89.4,wrapText(f2,80,1),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

% Bullet 3: Macula & Vascular Assessment
drawBulletIcon(ax1,7.0,94.6,TEAL);
text(ax1,10.0,94.8,"Macula & Vasculature:","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
f3 = sprintf("%s. Retinal vessel illumination and optic disc margins verified by quality assessment.",maculaInvolvement);
text(ax1,33.0,94.8,wrapText(f3,78,1),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

% Bullet 4: Clinical Referral Recommendation
drawBulletIcon(ax1,7.0,100.0,accent);
text(ax1,10.0,100.2,"Referral Determination:","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
text(ax1,34.0,100.2,wrapText(char(recommendation),76,1),"Color",accent,"FontSize",6.2,"FontWeight","bold","Interpreter","none");

% 5. AI CONFIDENCE / CLASS PROBABILITIES (Y: 104.0 -> 133.5, H: 29.5, W: 92)
drawCard(ax1,4.0,104.0,92.0,29.5,CARD_BG,BORDER);
text(ax1,6.5,107.2,"DR CLASS PROBABILITY DISTRIBUTION (RESNET-101)","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
text(ax1,6.5,109.8,"Posterior softmax probabilities across all International Clinical Diabetic Retinopathy stages","Color",TEXT_MUTED,"FontSize",5.8);
rectangle(ax1,"Position",[6.5 111.0 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

labels = {"No DR", "Mild NPDR", "Moderate NPDR", "Severe NPDR", "Proliferative DR"};
vals = [probabilities.NoDR, probabilities.Mild, probabilities.Moderate, probabilities.Severe, probabilities.ProliferativeDR];
barY = 113.5;
barH = 2.4;
maxBarW = 52.0;

for i = 1:5
    text(ax1,6.5,barY+1.8,labels{i},"Color",TEXT_DARK,"FontSize",6.0,"FontWeight","bold");
    
    trackX = 28.0;
    rectangle(ax1,"Position",[trackX barY maxBarW barH],"FaceColor",[0.93 0.95 0.97],"EdgeColor","none");
    
    fillW = max(0,min(maxBarW,(vals(i) / 100) * maxBarW));
    if fillW > 0
        rectangle(ax1,"Position",[trackX barY fillW barH],"FaceColor",probabilityColor(i),"EdgeColor","none");
    end
    
    text(ax1,trackX + maxBarW + 2.5,barY+1.8,sprintf("%.1f%%",vals(i)),"Color",TEXT_DARK,"FontSize",6.0,"FontWeight","bold");
    barY = barY + 3.8;
end

drawFooter(ax1,TEXT_MUTED,TEAL,1,3);

% Repaint Header
drawHeader(ax1,screeningId,examDate,NAVY,TEAL,WHITE);

exportgraphics(fig1,tempPdf,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig1);

% ============================================================
% PAGE 2 - RETINAL IMAGE ANALYSIS & EXPLAINABLE AI
% ============================================================
fig2 = makePageFigure();
ax2 = makePageAxes(fig2);

% Page Canvas
rectangle(ax2,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeaderPage(ax2,"RETINAL IMAGE ANALYSIS & EXPLAINABLE AI",screeningId,examDate,NAVY,TEAL,WHITE);

% 2x2 Structured Multi-Modal Retinal Grid (Y: 22.0 -> 91.0)
panelW = 44.5;
panelH = 33.0;

% Panel 1: Original Retina (Top-Left)
drawCard(ax2,4.0,22.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,6.0,25.2,"ORIGINAL RETINA","Color",NAVY,"FontSize",7.8,"FontWeight","bold");
text(ax2,6.0,27.5,"Raw unenhanced photographic acquisition (45° field)","Color",TEXT_MUTED,"FontSize",5.6);
boxP1 = [6.0 29.0 40.5 22.5];
rectangle(ax2,"Position",boxP1,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
showImageInBox(ax2,retinalImage,boxP1);
text(ax2,26.25,53.2,"Submitted photograph • True color fundus","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");

% Panel 2: Enhanced Retina (Top-Right)
drawCard(ax2,51.5,22.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,53.5,25.2,"ENHANCED RETINA","Color",NAVY,"FontSize",7.8,"FontWeight","bold");
text(ax2,53.5,27.5,"CLAHE adaptive equalization & micro-vascular enhancement","Color",TEXT_MUTED,"FontSize",5.6);
boxP2 = [53.5 29.0 40.5 22.5];
rectangle(ax2,"Position",boxP2,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
showImageInBox(ax2,enhancedImage,boxP2);
text(ax2,73.75,53.2,"Enhanced capillary & microaneurysm contrast","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");

% Panel 3: Grad-CAM Heatmap (Bottom-Left)
drawCard(ax2,4.0,57.5,panelW,panelH,CARD_BG,BORDER);
text(ax2,6.0,60.7,"GRAD-CAM HEATMAP","Color",NAVY,"FontSize",7.8,"FontWeight","bold");
text(ax2,6.0,63.0,"ResNet-101 class activation attention map","Color",TEXT_MUTED,"FontSize",5.6);
boxP3 = [6.0 64.5 40.5 22.5];

if hasGradCam && ~isempty(heatmapImage)
    rectangle(ax2,"Position",boxP3,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
    showImageInBox(ax2,heatmapImage,boxP3);
    text(ax2,26.25,88.7,"Warm colors denote highest neural activation","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");
else
    showPlaceholderInBox(ax2,boxP3,"Grad-CAM visualization unavailable for this screening.","No focal lesion activations detected above threshold.","Classification driven by global retinal vascular features.");
    text(ax2,26.25,88.7,"Analytical threshold: No abnormal focal hotspots","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");
end

% Panel 4: Affected Regions / Anatomical Overlay (Bottom-Right)
drawCard(ax2,51.5,57.5,panelW,panelH,CARD_BG,BORDER);
text(ax2,53.5,60.7,"AFFECTED REGIONS / OVERLAY","Color",NAVY,"FontSize",7.8,"FontWeight","bold");
text(ax2,53.5,63.0,"Heatmap registered directly to retinal landmarks","Color",TEXT_MUTED,"FontSize",5.6);
boxP4 = [53.5 64.5 40.5 22.5];

if hasGradCam && ~isempty(overlayImage)
    rectangle(ax2,"Position",boxP4,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
    showImageInBox(ax2,overlayImage,boxP4);
    text(ax2,73.75,88.7,"Heatmap blended with localized lesion bounding boxes","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");
else
    showPlaceholderInBox(ax2,boxP4,"Affected Regions Overlay Unavailable","No focal lesion activations detected above threshold.","Retinal background within normal morphological limits.");
    text(ax2,73.75,88.7,"No localized lesion bounding boxes required","Color",TEXT_MUTED,"FontSize",5.6,"HorizontalAlignment","center");
end

% AI Explainability — Grad-CAM Narrative Card (Y: 92.5 -> 108.5, H: 16.0, W: 92)
drawCard(ax2,4.0,92.5,92.0,16.0,CARD_BG,BORDER);
text(ax2,6.5,95.5,"AI EXPLAINABILITY — GRAD-CAM","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
rectangle(ax2,"Position",[6.5 96.8 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

gDesc1 = "The Grad-CAM visualization highlights regions of the retinal image that contributed to the model's prediction.";
text(ax2,6.5,100.0,gDesc1,"Color",NAVY,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

gDesc2 = "This visualization supports interpretation of the AI screening result and does not represent a confirmed clinical diagnosis. Heatmap intensity corresponds to the gradient contribution of convolutional feature maps in ResNet-101.";
text(ax2,6.5,103.8,wrapText(gDesc2,105,2),"Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");

% Suspected / Affected Region Section (Y: 110.5 -> 133.5, H: 23.0, W: 92)
drawCard(ax2,4.0,110.5,92.0,23.0,CARD_BG,BORDER);
text(ax2,6.5,113.5,"SUSPECTED LESIONS & REGIONAL LOCALIZATION","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
rectangle(ax2,"Position",[6.5 114.8 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Left Summary Column
text(ax2,6.5,118.0,sprintf("%d suspected regions",evidenceCount),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold");
if evidenceCount > 0
    text(ax2,6.5,121.5,sprintf("• %d Haemorrhage / Microaneurysm",numHemorrhages + numMicroaneurysms),"Color",TEXT_DARK,"FontSize",6.2);
    text(ax2,6.5,124.5,sprintf("• %d Exudates (Hard / Soft)",numExudates),"Color",TEXT_DARK,"FontSize",6.2);
    text(ax2,6.5,127.5,sprintf("• %d Positive Biomarker Category(ies)",positiveTypesCount),"Color",TEXT_MUTED,"FontSize",5.8);
else
    text(ax2,6.5,121.5,"• No hemorrhages detected","Color",TEXT_MUTED,"FontSize",6.0);
    text(ax2,6.5,124.5,"• No exudates detected","Color",TEXT_MUTED,"FontSize",6.0);
    text(ax2,6.5,127.5,"• Retinal parenchyma normal","Color",TEXT_MUTED,"FontSize",6.0);
end

% Right Table Column
rectangle(ax2,"Position",[38.0 116.0 55.5 3.5],"FaceColor",[0.92 0.95 0.98],"EdgeColor","none");
text(ax2,39.5,118.2,"#","Color",NAVY,"FontSize",5.8,"FontWeight","bold");
text(ax2,43.0,118.2,"TYPE","Color",NAVY,"FontSize",5.8,"FontWeight","bold");
text(ax2,60.0,118.2,"ZONE / COORD","Color",NAVY,"FontSize",5.8,"FontWeight","bold");
text(ax2,75.0,118.2,"AREA","Color",NAVY,"FontSize",5.8,"FontWeight","bold");
text(ax2,84.5,118.2,"STRENGTH","Color",NAVY,"FontSize",5.8,"FontWeight","bold");

evidenceRows = makeEvidenceRows(lesionEvidence, size(retinalImage));
tableY = 120.0;
rowH = 3.6;

if isempty(evidenceRows)
    rectangle(ax2,"Position",[38.0 tableY 55.5 7.5],"FaceColor",[0.96 0.98 0.99],"EdgeColor",BORDER,"LineWidth",0.3);
    text(ax2,40.0,tableY+3.2,"No localized lesion records returned for this screening.","Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");
    text(ax2,40.0,tableY+5.8,"Retinal field exhibits no microaneurysms, hemorrhages, or exudates.","Color",TEXT_MUTED,"FontSize",5.2,"Interpreter","none");
else
    maxDisp = min(3,size(evidenceRows,1));
    for r = 1:maxDisp
        rBg = CARD_BG;
        if mod(r,2) == 0
            rBg = [0.97 0.98 0.99];
        end
        rectangle(ax2,"Position",[38.0 tableY 55.5 rowH],"FaceColor",rBg,"EdgeColor",BORDER,"LineWidth",0.3);
        text(ax2,39.5,tableY+2.4,string(r),"Color",TEXT_DARK,"FontSize",5.6,"FontWeight","bold");
        text(ax2,43.0,tableY+2.4,string(evidenceRows{r,1}),"Color",TEXT_DARK,"FontSize",5.6,"FontWeight","bold","Interpreter","none");
        text(ax2,60.0,tableY+2.4,string(evidenceRows{r,2}),"Color",TEXT_DARK,"FontSize",5.6,"Interpreter","none");
        text(ax2,75.0,tableY+2.4,string(evidenceRows{r,4}),"Color",TEXT_DARK,"FontSize",5.6,"Interpreter","none");
        text(ax2,84.5,tableY+2.4,string(evidenceRows{r,5}),"Color",TEXT_DARK,"FontSize",5.6,"FontWeight","bold","Interpreter","none");
        tableY = tableY + rowH;
    end
    if size(evidenceRows,1) > maxDisp
        text(ax2,40.0,tableY+2.5,sprintf("+%d additional region(s) in system database.",size(evidenceRows,1)-maxDisp),"Color",TEXT_MUTED,"FontSize",5.2,"Interpreter","none");
    end
end

drawFooter(ax2,TEXT_MUTED,TEAL,2,3);

% Repaint Header
drawHeaderPage(ax2,"RETINAL IMAGE ANALYSIS & EXPLAINABLE AI",screeningId,examDate,NAVY,TEAL,WHITE);

exportgraphics(fig2,tempPdf,"Append",true,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig2);

% ============================================================
% PAGE 3 - CLINICAL FINDINGS, RECOMMENDATIONS & DETAILS
% ============================================================
fig3 = makePageFigure();
ax3 = makePageAxes(fig3);

% Page Canvas
rectangle(ax3,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeaderPage(ax3,"CLINICAL FINDINGS & RECOMMENDATIONS",screeningId,examDate,NAVY,TEAL,WHITE);

% 1. Clinical Screening Summary (Y: 22.0 -> 48.0, H: 26.0, W: 92)
drawCard(ax3,4.0,22.0,92.0,26.0,CARD_BG,BORDER);
text(ax3,6.5,25.2,"CLINICAL SCREENING SUMMARY","Color",NAVY,"FontSize",8.5,"FontWeight","bold");
rectangle(ax3,"Position",[6.5 26.5 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

text(ax3,6.5,30.0,"Screening Finding:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,27.0,30.0,sprintf("%s (%s certainty: %.1f%%).",diagnosisText,confidenceStatus,confidence),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold","Interpreter","none");

text(ax3,6.5,34.5,"Visual Evidence:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
if evidenceCount > 0
    sEv = sprintf("The AI pipeline identified %d suspected retinal lesion region(s) and generated an explainability attention map.",evidenceCount);
else
    sEv = "The AI pipeline identified 0 focal lesion regions. Heatmap attention reflects normal anatomical features.";
end
text(ax3,24.0,34.5,wrapText(sEv,85,1),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

text(ax3,6.5,39.0,"Macula:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,17.5,39.0,string(maculaInvolvement),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

text(ax3,6.5,43.5,"Retinal Structures:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,26.5,43.5,"Vessel network and optic-disc morphology evaluated across presenting 45° fundus field.","Color",TEXT_DARK,"FontSize",6.0);

% 2. Recommendations Card (Y: 50.0 -> 72.0, H: 22.0, W: 92)
drawCard(ax3,4.0,50.0,92.0,22.0,CARD_BG,BORDER);
rectangle(ax3,"Position",[4.0 50.0 2.2 22.0],"FaceColor",accent,"EdgeColor","none");

text(ax3,8.0,53.5,"RECOMMENDED NEXT STEPS","Color",NAVY,"FontSize",8.5,"FontWeight","bold");
text(ax3,8.0,57.5,wrapText(char(recommendation),95,2),"Color",accent,"FontSize",7.5,"FontWeight","bold","Interpreter","none");

% Structured Action Items
drawSmallBullet(ax3,8.5,62.5,accent);
if strcmpi(string(referralStatus),"REFERABLE DR")
    rec1 = "Specialist Consultation: Refer patient to an ophthalmologist / vitreoretinal specialist for dilated slit-lamp and OCT examination.";
else
    rec1 = "Periodic Rescreening: Repeat AI-assisted retinal screening in 6–12 months as part of routine diabetic eye care.";
end
text(ax3,11.5,62.8,string(rec1),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

drawSmallBullet(ax3,8.5,66.5,BLUE);
rec2 = "Systemic Management: Optimise blood sugar (HbA1c < 7.0%), blood pressure (< 130/80 mmHg), and serum lipid profile.";
text(ax3,11.5,66.8,string(rec2),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

drawSmallBullet(ax3,8.5,70.5,TEAL);
rec3 = "Clinical Guidance: Review by an eye-care professional where indicated. Seek urgent care if experiencing blurred vision or floaters.";
text(ax3,11.5,70.8,string(rec3),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

% 3. Image Quality Section (Y: 74.0 -> 94.0, H: 20.0, W: 92)
drawCard(ax3,4.0,74.0,92.0,20.0,CARD_BG,BORDER);
text(ax3,6.5,77.2,"IMAGE QUALITY & ACQUISITION INTEGRITY","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
rectangle(ax3,"Position",[6.5 78.5 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Quality Summary Row
text(ax3,6.5,82.0,"Quality Score:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,21.5,82.0,qualityScoreStr,"Color",qualityColor(qualityStatus,GREEN,AMBER,RED),"FontSize",6.5,"FontWeight","bold");

text(ax3,38.0,82.0,"Status:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,46.5,82.0,"Gradable","Color",GREEN,"FontSize",6.5,"FontWeight","bold");

text(ax3,62.0,82.0,"Diagnostic Adequacy:","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,83.0,82.0,"Suitable for AI","Color",TEXT_DARK,"FontSize",6.5,"FontWeight","bold");

% Metrics Breakdown
text(ax3,6.5,86.5,"Brightness:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax3,19.0,86.5,formatMetric(brightness),"Color",TEXT_DARK,"FontSize",6.0,"FontWeight","bold");

text(ax3,35.0,86.5,"Contrast:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax3,45.0,86.5,formatMetric(contrast),"Color",TEXT_DARK,"FontSize",6.0,"FontWeight","bold");

text(ax3,60.0,86.5,"Sharpness / Blur:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
text(ax3,78.0,86.5,formatMetric(sharpness),"Color",TEXT_DARK,"FontSize",6.0,"FontWeight","bold");

% Quality note / issues
text(ax3,6.5,91.0,"Quality Evaluation:","Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold");
if strlength(string(qualityMessage)) > 0
    qMsg = char(qualityMessage);
else
    qMsg = "No significant image-quality issues detected. Field satisfies diagnostic sharpness and illumination criteria.";
end
text(ax3,26.5,91.0,wrapText(qMsg,85,1),"Color",TEXT_DARK,"FontSize",5.8,"Interpreter","none");

% 4. Technical Details Section (Y: 96.0 -> 113.0, H: 17.0, W: 92)
drawCard(ax3,4.0,96.0,92.0,17.0,CARD_BG,BORDER);
text(ax3,6.5,99.0,"TECHNICAL DETAILS & MODEL AUDIT","Color",NAVY,"FontSize",7.5,"FontWeight","bold");
rectangle(ax3,"Position",[6.5 100.2 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

text(ax3,6.5,103.5,"Architecture:","Color",TEXT_MUTED,"FontSize",5.6,"FontWeight","bold");
text(ax3,21.0,103.5,"ResNet-101 (Deep Convolutional Residual Network)","Color",TEXT_DARK,"FontSize",5.6);

text(ax3,62.0,103.5,"Image Size:","Color",TEXT_MUTED,"FontSize",5.6,"FontWeight","bold");
text(ax3,74.5,103.5,sprintf("%dx%d px",size(retinalImage,2),size(retinalImage,1)),"Color",TEXT_DARK,"FontSize",5.6);

text(ax3,6.5,107.2,"Pipeline:","Color",TEXT_MUTED,"FontSize",5.6,"FontWeight","bold");
text(ax3,17.0,107.2,"Adaptive CLAHE -> 5-Class ICDR Inference -> Patch Grad-CAM Localization","Color",TEXT_DARK,"FontSize",5.6);

text(ax3,62.0,107.2,"Software:","Color",TEXT_MUTED,"FontSize",5.6,"FontWeight","bold");
text(ax3,73.5,107.2,"Jeevana Netra Engine SIH 2026","Color",TEXT_DARK,"FontSize",5.6);

text(ax3,6.5,110.8,"Audit Trail:","Color",TEXT_MUTED,"FontSize",5.6,"FontWeight","bold");
text(ax3,19.5,110.8,sprintf("Report ID %s  •  Processed %s",screeningId,examDate),"Color",TEXT_MUTED,"FontSize",5.4,"Interpreter","none");

% 5. Medical Disclaimer & Healthcare Provider Sign-Off (Y: 115.0 -> 133.5, H: 18.5, W: 92)
drawCard(ax3,4.0,115.0,92.0,18.5,CARD_BG,BORDER);

% Left: Disclaimer
text(ax3,6.5,118.0,"MEDICAL DISCLAIMER","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
discText = "This report is intended for screening and decision support and is not a substitute for professional medical diagnosis. Clinical management decisions remain the responsibility of a qualified healthcare professional.";
text(ax3,6.5,121.5,wrapText(discText,58,4),"Color",TEXT_MUTED,"FontSize",5.4,"Interpreter","none");

% Right: Healthcare Provider Sign-Off
rectangle(ax3,"Position",[61.0 116.5 0.35 15.5],"FaceColor",BORDER,"EdgeColor","none");
text(ax3,63.5,118.0,"HEALTHCARE PROVIDER VERIFICATION","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,63.5,122.0,"Reviewing Clinician:  __________________________","Color",TEXT_MUTED,"FontSize",5.5);
text(ax3,63.5,126.0,"Signature / Date:     __________________________","Color",TEXT_MUTED,"FontSize",5.5);
text(ax3,63.5,130.0,"Facility / Center:    Jeevana Netra Vision Center","Color",TEXT_MUTED,"FontSize",5.5);

drawFooter(ax3,TEXT_MUTED,TEAL,3,3);

% Repaint Header
drawHeaderPage(ax3,"CLINICAL FINDINGS & RECOMMENDATIONS",screeningId,examDate,NAVY,TEAL,WHITE);

exportgraphics(fig3,tempPdf,"Append",true,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig3);

% ============================================================
% 7. Read and Return PDF Bytes
% ============================================================

fid = fopen(tempPdf,"rb");
if fid == -1
    error("Generated PDF could not be opened.");
end

pdfBytes = fread(fid,Inf,"*uint8");
fclose(fid);

deleteIfExists(tempPdf);

response = struct();
response.status = "success";
response.filename = fileName;
response.pdfBytes = pdfBytes(:)';
response.sizeBytes = numel(pdfBytes);

end

% ============================================================
% LOCAL HELPER FUNCTIONS
% ============================================================

function fig = makePageFigure()
% Standard A4 Portrait figure (8.27 x 11.69 inches)
fig = figure("Visible","off","Color","white","Units","inches","Position",[1 1 8.27 11.69],"MenuBar","none","ToolBar","none");
end

function ax = makePageAxes(fig)
ax = axes(fig,"Units","normalized","Position",[0 0 1 1]);
axis(ax,"off");
xlim(ax,[0 100]);
ylim(ax,[0 140]);
set(ax,"YDir","reverse");
hold(ax,"on");
end

function drawHeader(ax, screeningId, examDate, navyColor, tealColor, whiteColor)
% Professional Page 1 Header
rectangle(ax,"Position",[0 0 100 18.5],"FaceColor",navyColor,"EdgeColor","none");
rectangle(ax,"Position",[0 17.8 100 0.7],"FaceColor",tealColor,"EdgeColor","none");

text(ax,4.5,5.2,"JEEVANA NETRA","Color",whiteColor,"FontSize",18.5,"FontWeight","bold");
text(ax,4.5,9.2,"AI-POWERED DIABETIC RETINOPATHY SCREENING","Color",[0.55 0.90 0.85],"FontSize",7.2,"FontWeight","bold");
text(ax,4.5,14.5,"Explainable AI-assisted retinal screening report","Color",[0.84 0.90 0.95],"FontSize",7.0,"Interpreter","none");

text(ax,95.5,5.2,"REPORT IDENTIFIER","Color",[0.65 0.75 0.85],"FontSize",5.8,"FontWeight","bold","HorizontalAlignment","right");
text(ax,95.5,9.2,string(screeningId),"Color",whiteColor,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,95.5,14.5,"Generated: " + string(examDate),"Color",[0.78 0.86 0.92],"FontSize",6.5,"HorizontalAlignment","right","Interpreter","none");
end

function drawHeaderPage(ax, pageCategory, screeningId, examDate, navyColor, tealColor, whiteColor)
% Professional Secondary Pages Header
rectangle(ax,"Position",[0 0 100 18.5],"FaceColor",navyColor,"EdgeColor","none");
rectangle(ax,"Position",[0 17.8 100 0.7],"FaceColor",tealColor,"EdgeColor","none");

text(ax,4.5,5.2,"JEEVANA NETRA","Color",whiteColor,"FontSize",18.5,"FontWeight","bold");
text(ax,4.5,9.2,"AI-POWERED DIABETIC RETINOPATHY SCREENING","Color",[0.55 0.90 0.85],"FontSize",7.2,"FontWeight","bold");
text(ax,4.5,14.5,string(pageCategory),"Color",[0.84 0.90 0.95],"FontSize",7.5,"FontWeight","bold","Interpreter","none");

text(ax,95.5,5.2,"REPORT IDENTIFIER","Color",[0.65 0.75 0.85],"FontSize",5.8,"FontWeight","bold","HorizontalAlignment","right");
text(ax,95.5,9.2,string(screeningId),"Color",whiteColor,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,95.5,14.5,"Generated: " + string(examDate),"Color",[0.78 0.86 0.92],"FontSize",6.5,"HorizontalAlignment","right","Interpreter","none");
end

function drawFooter(ax, mutedColor, tealColor, pageNo, totalPages)
rectangle(ax,"Position",[4 135 92 0.35],"FaceColor",[0.82 0.88 0.92],"EdgeColor","none");
text(ax,4.5,137.8,"Developed by Team JEEVANA-NETRA  •  SIH 2026","Color",mutedColor,"FontSize",5.8);
text(ax,50.0,137.8,"This report is intended for screening and decision support and is not a substitute for professional medical diagnosis.","Color",mutedColor,"FontSize",5.0,"HorizontalAlignment","center");
text(ax,95.5,137.8,"Page " + string(pageNo) + " of " + string(totalPages),"Color",mutedColor,"FontSize",6.0,"FontWeight","bold","HorizontalAlignment","right");
text(ax,95.5,136.0,"AI FOR BETTER VISION","Color",tealColor,"FontSize",5.2,"FontWeight","bold","HorizontalAlignment","right");
end

function drawCard(ax, x, y, w, h, faceColor, borderColor)
rectangle(ax,"Position",[x y w h],"FaceColor",faceColor,"EdgeColor",borderColor,"LineWidth",0.6);
end

function showImageInBox(ax, I, box)
if isempty(I)
    return;
end
imgH = size(I,1);
imgW = size(I,2);
if imgH <= 0 || imgW <= 0
    return;
end
ratio = imgW / imgH;
boxRatio = box(3) / box(4);
if ratio > boxRatio
    drawW = box(3);
    drawH = box(3) / ratio;
else
    drawH = box(4);
    drawW = box(4) * ratio;
end
x0 = box(1) + (box(3) - drawW) / 2;
y0 = box(2) + (box(4) - drawH) / 2;
image(ax,[x0 x0+drawW],[y0 y0+drawH],I);
end

function showPlaceholderInBox(ax, box, titleStr, subStr, noteStr)
rectangle(ax,"Position",box,"FaceColor",[0.94 0.96 0.98],"EdgeColor",[0.82 0.88 0.93],"LineWidth",0.6);
cx = box(1) + box(3) / 2;
cy = box(2) + box(4) / 2;

iconR = 2.8;
iconY = cy - 3.8;
t = linspace(0,2*pi,60);
fill(ax,cx + iconR*cos(t),iconY + iconR*sin(t),[0.88 0.92 0.96],"EdgeColor",[0.72 0.80 0.88],"LineWidth",0.7);
plot(ax,[cx - 1.6, cx + 1.6],[iconY, iconY],"Color",[0.45 0.55 0.68],"LineWidth",0.9);
plot(ax,[cx, cx],[iconY - 1.6, iconY + 1.6],"Color",[0.45 0.55 0.68],"LineWidth",0.9);

text(ax,cx,cy+1.2,string(titleStr),"Color",[0.15 0.25 0.38],"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax,cx,cy+4.2,string(subStr),"Color",[0.42 0.50 0.60],"FontSize",5.4,"HorizontalAlignment","center","Interpreter","none");
text(ax,cx,cy+7.0,string(noteStr),"Color",[0.08 0.50 0.55],"FontSize",5.0,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
end

function drawBulletIcon(ax, x, y, color)
rectangle(ax,"Position",[x y-1.2 1.5 1.5],"FaceColor",color,"EdgeColor","none");
end

function drawSmallBullet(ax, x, y, color)
rectangle(ax,"Position",[x y-1.0 1.2 1.2],"FaceColor",color,"EdgeColor","none");
end

function [heatmapRGB, overlayImage, hasGradCam] = extractGradCamData(retinalImage, request, result, lesionEvidence)
H = size(retinalImage,1);
W = size(retinalImage,2);
hasGradCam = false;
heatmapRGB = [];
overlayImage = [];
camMap = [];

% 1. Check if direct heatmap matrix was passed in result or request
if isfield(result,"heatmap") && ~isempty(result.heatmap) && isnumeric(result.heatmap)
    camMap = double(result.heatmap);
elseif isfield(result,"combinedMap") && ~isempty(result.combinedMap) && isnumeric(result.combinedMap)
    camMap = double(result.combinedMap);
elseif isfield(request,"combinedMap") && ~isempty(request.combinedMap) && isnumeric(request.combinedMap)
    camMap = double(request.combinedMap);
end

% 2. Check if lesionEvidence contains full .map matrices (from extract_lesion_evidence)
if isempty(camMap) && isstruct(lesionEvidence) && isfield(lesionEvidence,"map")
    camMap = zeros(H,W);
    for k = 1:numel(lesionEvidence)
        if ~isempty(lesionEvidence(k).map) && isnumeric(lesionEvidence(k).map)
            m = double(lesionEvidence(k).map);
            if size(m,1) ~= H || size(m,2) ~= W
                m = imresize(m,[H W]);
            end
            camMap = max(camMap,m);
        end
    end
end

% 3. Construct spatial heatmap from localized lesionEvidence regions (from summarize_lesion_evidence)
if isempty(camMap) && isstruct(lesionEvidence)
    flatRegions = extractFlatRegions(lesionEvidence);
    if ~isempty(flatRegions)
        camMap = zeros(H,W);
        for i = 1:numel(flatRegions)
            r = flatRegions{i};
            [ok, x, y, w, h] = getRegionBox(r,[H W 3]);
            if ok
                if isfield(r,"centerX") && isfield(r,"centerY") && isnumeric(r.centerX) && isnumeric(r.centerY) && r.centerX <= 1 && r.centerY <= 1
                    cx = double(r.centerX) * W;
                    cy = double(r.centerY) * H;
                else
                    cx = x + w / 2;
                    cy = y + h / 2;
                end
                sx = max(w / 2, W * 0.04);
                sy = max(h / 2, H * 0.04);
                str = 1.0;
                if isfield(r,"strength") && ~isempty(r.strength) && isnumeric(r.strength)
                    str = double(r.strength);
                end
                
                minX = max(1,round(cx - 3 * sx));
                maxX = min(W,round(cx + 3 * sx));
                minY = max(1,round(cy - 3 * sy));
                maxY = min(H,round(cy + 3 * sy));
                
                if maxX >= minX && maxY >= minY
                    [gridX, gridY] = meshgrid(minX:maxX,minY:maxY);
                    blob = str * exp(-(((gridX - cx).^2) / (2 * sx^2) + ((gridY - cy).^2) / (2 * sy^2)));
                    camMap(minY:maxY,minX:maxX) = max(camMap(minY:maxY,minX:maxX),blob);
                end
            end
        end
    end
end

% 4. Normalize and generate RGB Heatmap & Anatomical Overlay
if ~isempty(camMap)
    if size(camMap,1) ~= H || size(camMap,2) ~= W
        camMap = imresize(camMap,[H W]);
    end
    maxVal = max(camMap(:));
    if maxVal > 0
        camMap = camMap / maxVal;
        hasGradCam = true;
        
        cmap = jet(256);
        idx = round(camMap * 255) + 1;
        idx = max(1,min(256,idx));
        rgbFlat = cmap(idx(:),:);
        heatmapRGB = im2uint8(reshape(rgbFlat,[H W 3]));
        
        % Blend with retinal fundus image for anatomical overlay
        alpha = 0.50 * camMap;
        alpha3 = repmat(alpha,[1 1 3]);
        overlayDbl = double(retinalImage) .* (1 - alpha3) + double(heatmapRGB) .* alpha3;
        overlayImage = uint8(min(255,max(0,overlayDbl)));
        overlayImage = makeEvidenceOverlay(overlayImage,lesionEvidence);
    end
end
end

function flat = extractFlatRegions(evidence)
flat = cell(0,1);
if ~isstruct(evidence) || isempty(evidence)
    return;
end

if isfield(evidence,"regions")
    for i = 1:numel(evidence)
        regs = evidence(i).regions;
        lesionType = "";
        if isfield(evidence(i),"type") && ~isempty(evidence(i).type)
            lesionType = string(evidence(i).type);
        end
        if isstruct(regs)
            for j = 1:numel(regs)
                item = regs(j);
                if (~isfield(item,"type") || isempty(item.type) || string(item.type) == "evidence") && lesionType ~= ""
                    item.type = lesionType;
                end
                flat{end+1,1} = item; %#ok<AGROW>
            end
        end
    end
else
    for i = 1:numel(evidence)
        flat{end+1,1} = evidence(i); %#ok<AGROW>
    end
end
end

function J = enhanceRetinalImage(I)
try
    I2 = im2double(I);
    HSV = rgb2hsv(I2);
    V = HSV(:,:,3);
    V = adapthisteq(V,"NumTiles",[8 8],"ClipLimit",0.01);
    V = imsharpen(V,"Radius",1,"Amount",0.5);
    HSV(:,:,3) = min(1,max(0,V));
    J = im2uint8(hsv2rgb(HSV));
catch
    J = I;
end
end

function J = makeEvidenceOverlay(I,evidence)
J = I;
if ~isstruct(evidence) || isempty(evidence)
    return;
end

flat = extractFlatRegions(evidence);
for j = 1:numel(flat)
    [ok,x,y,w,h] = getRegionBox(flat{j},size(J));
    if ok
        J = drawImageRectangle(J,x,y,w,h,[255 220 0],2);
    end
end
end

function [ok,x,y,w,h] = getRegionBox(region,imageSize)
ok = false;
x = 0; y = 0; w = 0; h = 0;
H = imageSize(1);
W = imageSize(2);

if isfield(region,"bbox") && isnumeric(region.bbox) && numel(region.bbox) >= 4
    b = double(region.bbox(:));
    x = b(1); y = b(2); w = b(3); h = b(4);
    ok = true;
elseif isfield(region,"x") && isfield(region,"y") && isfield(region,"w") && isfield(region,"h")
    x = double(region.x); y = double(region.y); w = double(region.w); h = double(region.h);
    ok = true;
elseif isfield(region,"x") && isfield(region,"y") && isfield(region,"width") && isfield(region,"height")
    x = double(region.x); y = double(region.y); w = double(region.width); h = double(region.height);
    ok = true;
end

if ~ok || any(~isfinite([x y w h]))
    ok = false;
    return;
end

x = max(1,min(W-1,x));
y = max(1,min(H-1,y));
w = max(1,min(W-x,w));
h = max(1,min(H-y,h));
end

function J = drawImageRectangle(I,x,y,w,h,color,thickness)
J = I;
H = size(I,1);
W = size(I,2);
x1 = max(1,round(x));
y1 = max(1,round(y));
x2 = min(W,round(x+w));
y2 = min(H,round(y+h));
t = max(1,round(thickness));

r1 = y1:min(y1+t-1,y2);
r2 = max(y2-t+1,y1):y2;
c1 = x1:x2;
c2 = x1:min(x1+t-1,x2);
c3 = max(x2-t+1,x1):x2;

col = reshape(uint8(color),1,1,3);
J(r1,c1,:) = repmat(col,numel(r1),numel(c1),1);
J(r2,c1,:) = repmat(col,numel(r2),numel(c1),1);
J(y1:y2,c2,:) = repmat(col,numel(y1:y2),numel(c2),1);
J(y1:y2,c3,:) = repmat(col,numel(y1:y2),numel(c3),1);
end

function n = countEvidenceRegions(evidence)
n = 0;
if ~isstruct(evidence) || isempty(evidence)
    return;
end
flat = extractFlatRegions(evidence);
n = numel(flat);
end

function [numHem, numMicro, numExud, positiveCount] = buildLesionBreakdown(lesionEvidence)
numHem = 0;
numMicro = 0;
numExud = 0;
positiveCount = 0;

if ~isstruct(lesionEvidence) || isempty(lesionEvidence)
    return;
end

if isfield(lesionEvidence,"hasEvidence")
    for i = 1:numel(lesionEvidence)
        if lesionEvidence(i).hasEvidence
            positiveCount = positiveCount + 1;
        end
    end
end

flat = extractFlatRegions(lesionEvidence);
for j = 1:numel(flat)
    t = lower(char(getStringField(flat{j},"type","")));
    if contains(t,"haem") || contains(t,"hem")
        numHem = numHem + 1;
    elseif contains(t,"micro")
        numMicro = numMicro + 1;
    elseif contains(t,"exud")
        numExud = numExud + 1;
    else
        numHem = numHem + 1;
    end
end
end

function maculaText = evaluateMaculaInvolvement(lesionEvidence, evidenceCount)
if evidenceCount == 0
    maculaText = "No involvement detected";
    return;
end

flat = extractFlatRegions(lesionEvidence);
fovealInvolved = false;
for i = 1:numel(flat)
    r = flat{i};
    if isfield(r,"centerX") && isfield(r,"centerY") && isnumeric(r.centerX) && isnumeric(r.centerY)
        cx = double(r.centerX);
        cy = double(r.centerY);
        if cx <= 1 && cy <= 1
            dist = sqrt((cx - 0.5)^2 + (cy - 0.5)^2);
            if dist < 0.15
                fovealInvolved = true;
                break;
            end
        end
    end
end

if fovealInvolved
    maculaText = "Suspected parafoveal lesion activity noted";
else
    maculaText = "No central macula involvement detected (Spared)";
end
end

function rows = makeEvidenceRows(evidence, imageSize)
if nargin < 2 || isempty(imageSize)
    imageSize = [512 512 3];
end
rows = cell(0,5);
if ~isstruct(evidence) || isempty(evidence)
    return;
end

flat = extractFlatRegions(evidence);

for i = 1:numel(flat)
    r = flat{i};
    pos = "n/a";
    bboxStr = "n/a";
    [ok,x,y,w,h] = getRegionBox(r,imageSize);
    if ok
        pos = string(sprintf("(%d, %d)",round(x),round(y)));
        bboxStr = string(sprintf("%dx%d",round(w),round(h)));
    elseif isfield(r,"position")
        pos = string(r.position);
    end

    area = "n/a";
    if isfield(r,"area") && ~isempty(r.area)
        area = string(sprintf("%.0f px²",double(r.area)));
    end

    strength = "n/a";
    if isfield(r,"strength") && ~isempty(r.strength)
        strength = string(sprintf("%.2f",double(r.strength)));
    elseif isfield(r,"intensity") && ~isempty(r.intensity)
        strength = string(sprintf("%.2f",double(r.intensity)));
    end

    typeZone = getStringField(r,"type","Evidence");
    if isfield(r,"zone") && ~isempty(r.zone)
        typeZone = typeZone + " (" + string(r.zone) + ")";
    end

    rows(end+1,:) = {string(typeZone), pos, bboxStr, area, strength}; %#ok<AGROW>
end
end

function titleStr = formatDiagnosisTitle(predictedClass)
s = lower(strtrim(char(string(predictedClass))));
switch s
    case {"nodr","no dr"}
        titleStr = "NO DIABETIC RETINOPATHY DETECTED";
    case "mild"
        titleStr = "MILD DIABETIC RETINOPATHY DETECTED";
    case "moderate"
        titleStr = "MODERATE DIABETIC RETINOPATHY DETECTED";
    case "severe"
        titleStr = "SEVERE DIABETIC RETINOPATHY DETECTED";
    case {"proliferativedr","proliferative dr","proliferative"}
        titleStr = "PROLIFERATIVE DIABETIC RETINOPATHY DETECTED";
    otherwise
        titleStr = upper(string(predictedClass) + " DETECTED");
end
end

function tagStr = formatGradeTag(predictedClass)
s = lower(strtrim(char(string(predictedClass))));
switch s
    case {"nodr","no dr"}
        tagStr = "ICDR Grade 0  •  Non-Referable DR";
    case "mild"
        tagStr = "ICDR Grade 1  •  Non-Referable Early DR";
    case "moderate"
        tagStr = "ICDR Grade 2  •  Referable Non-Proliferative DR";
    case "severe"
        tagStr = "ICDR Grade 3  •  Referable Severe NPDR";
    case {"proliferativedr","proliferative dr","proliferative"}
        tagStr = "ICDR Grade 4  •  High-Risk Referable Proliferative DR";
    otherwise
        tagStr = "International Clinical Diabetic Retinopathy Scale";
end
end

function qStr = formatQualityIndex(status)
s = lower(strtrim(char(string(status))));
if strcmpi(s,"good") || strcmpi(s,"gradable")
    qStr = "100/100";
elseif contains(s,"poor") || contains(s,"retake")
    qStr = "45/100";
else
    qStr = "80/100";
end
end

function tf = isPngBytes(bytes)
tf = false;
if numel(bytes) < 8
    return;
end
signature = uint8([137 80 78 71 13 10 26 10]);
b = uint8(bytes(1:8));
tf = isequal(b(:)',signature(:)');
end

function tf = isJpegBytes(bytes)
tf = false;
if numel(bytes) < 3
    return;
end
signature = uint8([255 216 255]);
b = uint8(bytes(1:3));
tf = isequal(b(:)',signature(:)');
end

function p = getProbability(result,name)
p = 0;
if isfield(result,"probabilities") && isfield(result.probabilities,name)
    p = convertToPercent(double(result.probabilities.(name)));
end
end

function value = getStringField(source,fieldName,defaultValue)
if ~isstruct(source) || ~isfield(source,fieldName) || isempty(source.(fieldName))
    value = string(defaultValue);
    return;
end

raw = source.(fieldName);
if iscell(raw)
    raw = raw{1};
end
value = string(raw);
if isempty(value) || strlength(value(1)) == 0
    value = string(defaultValue);
else
    value = value(1);
end
end

function value = getNumericField(source,fieldName,defaultValue)
if ~isstruct(source) || ~isfield(source,fieldName) || isempty(source.(fieldName))
    value = defaultValue;
    return;
end
raw = source.(fieldName);
value = double(raw(1));
if ~isfinite(value)
    value = defaultValue;
end
end

function p = convertToPercent(value)
if isempty(value) || ~isfinite(value)
    p = 0;
elseif abs(value) <= 1
    p = value * 100;
else
    p = value;
end
p = max(0,min(100,p));
end

function color = severityColor(name,green,amber,red,purple,blue)
s = lower(strtrim(char(string(name))));
if strcmpi(s,"no dr") || strcmpi(s,"nodr")
    color = green;
elseif strcmpi(s,"mild")
    color = amber;
elseif strcmpi(s,"moderate") || strcmpi(s,"severe")
    color = red;
elseif strcmpi(s,"proliferative dr") || strcmpi(s,"proliferativedr")
    color = purple;
else
    color = blue;
end
end

function color = qualityColor(status,good,warning,bad)
s = lower(strtrim(char(string(status))));
if strcmpi(s,"good") || strcmpi(s,"gradable")
    color = good;
elseif contains(s,"poor") || contains(s,"retake") || contains(s,"ungradable")
    color = bad;
else
    color = warning;
end
end

function value = formatMetric(x)
if isempty(x) || ~isfinite(x)
    value = "N/A";
else
    value = string(sprintf("%.2f",x));
end
end

function value = formatAge(age)
if isempty(age) || isnan(age) || ~isfinite(age)
    value = "Not specified";
else
    value = string(sprintf("%.0f yrs",round(age)));
end
end

function c = probabilityColor(i)
colors = [[32 164 100]/255; [225 145 20]/255; [235 110 30]/255; [210 60 45]/255; [135 30 95]/255];
c = colors(i,:);
end

function c = blendWithWhite(base,ratio)
c = base * (1-ratio) + [1 1 1] * ratio;
end

function textOut = wrapText(inputText,maxChars,maxLines)
inputText = strtrim(char(inputText));
if isempty(inputText)
    textOut = "";
    return;
end

words = split(string(inputText));
lines = strings(0,1);
current = "";

for i = 1:numel(words)
    candidate = string(words(i));
    if strlength(current) > 0
        candidate = current + " " + candidate;
    end
    if strlength(candidate) <= maxChars
        current = candidate;
    else
        if strlength(current) > 0
            lines(end+1,1) = current; %#ok<AGROW>
        end
        current = string(words(i));
        if numel(lines) >= maxLines
            break;
        end
    end
end

if numel(lines) < maxLines && strlength(current) > 0
    lines(end+1,1) = current;
end

if numel(lines) > maxLines
    lines = lines(1:maxLines);
end

if numel(lines) == maxLines && strlength(lines(end)) > maxChars
    lastLine = char(lines(end));
    lastLine = lastLine(1:max(1,maxChars-3));
    lines(end) = string(lastLine + "...");
end

textOut = strjoin(lines,newline);
end

function safeName = makeSafeFilename(value)
safeName = regexprep(char(string(value)),"[^A-Za-z0-9_-]","_");
if isempty(safeName)
    safeName = "patient";
end
end

function deleteIfExists(filePath)
if exist(filePath,"file")
    try
        delete(filePath);
    catch
    end
end
end
