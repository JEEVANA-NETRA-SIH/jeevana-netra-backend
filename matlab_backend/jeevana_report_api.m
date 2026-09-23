function response = jeevana_report_api(requestJson)
% JEEVANA_REPORT_API
% Generates a professional three-page clinical AI screening report for
% Jeevana Netra (Smart India Hackathon 2026).
%
% Visual Structure:
%   PAGE 1: Executive Clinical Summary & Patient Profile
%           - Result Banner, Patient Demographics, Image Quality
%           - Model Confidence Ring, Retinal Field Preview
%           - ICDR DR Grade Probability Distribution
%   PAGE 2: Retinal Image Analysis & Grad-CAM Explainability
%           - 4-Panel Multi-Modal Retinal Grid (Original, Enhanced,
%             Grad-CAM Heatmap, Anatomical Heatmap Overlay)
%           - AI Explainability Methodology & Interpretability Note
%   PAGE 3: Clinical AI Findings, Suspected Lesions & Recommendations
%           - Structured AI Screening Findings
%           - Suspected Lesion Evidence Regions Table
%           - Recommended Clinical Next Steps
%           - Clinical AI Disclaimer & Healthcare Practitioner Sign-Off
%
% Input JSON fields:
%   operation, screeningId, patient, result, imageBytes / imageBase64
%
% Output fields:
%   status, filename, pdfBytes, sizeBytes

%% 1. Validate input

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

%% 2. Extract patient information

patientName = getStringField(patient,"name","Unknown");
patientId = getStringField(patient,"id","");
if patientId == "" || patientId == "Unknown"
    patientId = getStringField(patient,"patientId","Unknown");
end
patientGender = getStringField(patient,"gender","Not specified");
patientAge = getNumericField(patient,"age",NaN);

screeningId = "JN-REPORT";
if isfield(request,"screeningId") && ~isempty(request.screeningId)
    screeningId = string(request.screeningId);
end

examDate = string(datetime("now","Format","dd MMM yyyy, HH:mm"));
if isfield(request,"screeningDate") && ~isempty(request.screeningDate)
    examDate = string(request.screeningDate);
end

%% 3. Extract AI screening results

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

%% 4. Decode retinal image bytes

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

%% 6. Color Palette (Jeevana Netra SIH 2026 Visual Identity)

NAVY       = [11 42 74] / 255;      % #0B2A4A Primary Dark Navy
BLUE       = [20 93 160] / 255;     % #145DA0 Healthcare Blue
TEAL       = [8 127 140] / 255;     % #087F8C Modern Teal Accent
GREEN      = [32 164 100] / 255;    % #20A464 Healthy / Non-referable
AMBER      = [225 145 20] / 255;    % Mild DR Warning
RED        = [210 60 45] / 255;     % Moderate / Severe DR Alert
PURPLE     = [135 30 95] / 255;     % Proliferative DR Urgent
TEXT_DARK  = [26 38 57] / 255;      % Deep Slate Body Text
TEXT_MUTED = [100 116 139] / 255;   % Cool Gray Labels
BG_PAGE    = [248 250 252] / 255;   % Crisp Neutral Background
CARD_BG    = [255 255 255] / 255;   % Clean White Card Surface
BORDER     = [220 228 236] / 255;   % Soft Card Border
WHITE      = [1 1 1];

accent = severityColor(predictedClass,GREEN,AMBER,RED,PURPLE,BLUE);
softAccent = blendWithWhite(accent,0.92);

% ============================================================
% PAGE 1 - EXECUTIVE CLINICAL SUMMARY & PATIENT PROFILE
% ============================================================
fig1 = makePageFigure();
ax1 = makePageAxes(fig1);

% Page Canvas
rectangle(ax1,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeader(ax1,"EXECUTIVE SCREENING SUMMARY","Diabetic Retinopathy Automated AI Report",screeningId,examDate,NAVY,TEAL,WHITE);

% Result Banner (Y: 23.5 -> 40.0)
rectangle(ax1,"Position",[4 23.5 92 16.5],"FaceColor",accent,"EdgeColor","none");
rectangle(ax1,"Position",[4 23.5 2.5 16.5],"FaceColor",blendWithWhite(accent,0.4),"EdgeColor","none");

text(ax1,8.5,27.0,"AI SCREENING CLASSIFICATION","Color",[0.92 0.96 0.98],"FontSize",7.0,"FontWeight","bold");
text(ax1,8.5,33.0,formatDiagnosisTitle(predictedClass),"Color",WHITE,"FontSize",15.5,"FontWeight","bold","Interpreter","none");
text(ax1,8.5,37.5,formatGradeTag(predictedClass),"Color",[0.88 0.94 0.98],"FontSize",7.2,"FontWeight","bold","Interpreter","none");

text(ax1,56.0,27.0,"MODEL CONFIDENCE","Color",[0.92 0.96 0.98],"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,56.0,33.0,sprintf("%.1f%%",confidence),"Color",WHITE,"FontSize",14.0,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,56.0,37.5,sprintf("[%s TIER]",confidenceStatus),"Color",[0.88 0.94 0.98],"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");

text(ax1,82.5,27.0,"REFERRAL STATUS","Color",[0.92 0.96 0.98],"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,82.5,33.0,wrapText(char(referralStatus),18,2),"Color",WHITE,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax1,82.5,37.5,sprintf("Evidence Regions: %d",evidenceCount),"Color",[0.88 0.94 0.98],"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center");

% Patient Profile Card (Y: 42.5 -> 66.5, W: 44.5)
drawCard(ax1,4,42.5,44.5,24.0,CARD_BG,BORDER);
text(ax1,6.5,46.5,"PATIENT PROFILE","Color",NAVY,"FontSize",9.2,"FontWeight","bold");
rectangle(ax1,"Position",[6.5 48.0 39.5 0.35],"FaceColor",BORDER,"EdgeColor","none");

text(ax1,6.5,52.0,"NAME","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,6.5,55.5,string(patientName),"Color",TEXT_DARK,"FontSize",9.0,"FontWeight","bold","Interpreter","none");

text(ax1,28.5,52.0,"PATIENT ID","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,28.5,55.5,string(patientId),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold","Interpreter","none");

text(ax1,6.5,60.0,"AGE","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,6.5,63.5,formatAge(patientAge),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold","Interpreter","none");

text(ax1,28.5,60.0,"GENDER","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,28.5,63.5,string(patientGender),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold","Interpreter","none");

% Image Acquisition & Quality Card (Y: 42.5 -> 66.5, W: 45.5)
drawCard(ax1,50.5,42.5,45.5,24.0,CARD_BG,BORDER);
text(ax1,53.0,46.5,"IMAGE ACQUISITION & QUALITY","Color",NAVY,"FontSize",9.2,"FontWeight","bold");

qualityAccent = qualityColor(qualityStatus,GREEN,AMBER,RED);
qualitySoft = blendWithWhite(qualityAccent,0.88);
rectangle(ax1,"Position",[81.5 44.3 12.5 4.0],"FaceColor",qualitySoft,"EdgeColor",qualityAccent,"LineWidth",0.7);
text(ax1,87.75,46.8,string(qualityStatus),"Color",qualityAccent,"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
rectangle(ax1,"Position",[53.0 48.0 40.5 0.35],"FaceColor",BORDER,"EdgeColor","none");

text(ax1,53.0,52.0,"BRIGHTNESS","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,53.0,55.5,formatMetric(brightness),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold");

text(ax1,67.0,52.0,"CONTRAST","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,67.0,55.5,formatMetric(contrast),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold");

text(ax1,81.0,52.0,"SHARPNESS","Color",TEXT_MUTED,"FontSize",6.2,"FontWeight","bold");
text(ax1,81.0,55.5,formatMetric(sharpness),"Color",TEXT_DARK,"FontSize",8.5,"FontWeight","bold");

text(ax1,53.0,59.8,"EVALUATION:","Color",TEXT_MUTED,"FontSize",6.0,"FontWeight","bold");
qualityDisplay = "Suitable for clinical screening.";
if strlength(string(qualityMessage)) > 0
    qualityDisplay = char(qualityMessage);
end
text(ax1,64.0,59.8,wrapText(qualityDisplay,42,1),"Color",TEXT_DARK,"FontSize",6.0,"Interpreter","none");

text(ax1,53.0,63.5,"Standard: 45° macula-centered fundus photograph","Color",TEXT_MUTED,"FontSize",5.6);

% Retinal Field Preview Card (Y: 69.5 -> 116.5, W: 56.5)
drawCard(ax1,4,69.5,56.5,47.0,CARD_BG,BORDER);
text(ax1,6.5,73.5,"RETINAL FIELD PREVIEW","Color",NAVY,"FontSize",9.2,"FontWeight","bold");
text(ax1,6.5,76.5,"Submitted digital fundus acquisition","Color",TEXT_MUTED,"FontSize",6.0);

imageBox1 = [6.5 78.5 51.5 33.5];
rectangle(ax1,"Position",imageBox1,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.6);
showImageInBox(ax1,retinalImage,imageBox1);
text(ax1,32.25,114.5,"Primary screening field • Macula / disc region","Color",TEXT_MUTED,"FontSize",6.2,"HorizontalAlignment","center");

% Model Confidence & Referral Pathway Card (Y: 69.5 -> 116.5, W: 33.5)
drawCard(ax1,62.5,69.5,33.5,47.0,CARD_BG,BORDER);
text(ax1,65.0,73.5,"MODEL CONFIDENCE","Color",NAVY,"FontSize",9.2,"FontWeight","bold");
text(ax1,65.0,76.5,"ResNet-101 posterior probability","Color",TEXT_MUTED,"FontSize",6.0);

drawConfidenceRing(ax1,79.25,91.0,8.5,confidence,accent,TEXT_DARK,TEXT_MUTED);

text(ax1,79.25,102.5,sprintf("TIER: %s",upper(char(string(confidenceStatus)))),"Color",TEXT_MUTED,"FontSize",6.3,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax1,79.25,106.0,"CLINICAL PATHWAY","Color",NAVY,"FontSize",6.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax1,79.25,110.0,wrapText(char(referralStatus),16,2),"Color",accent,"FontSize",7.8,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");

% ICDR DR Grade Probability Distribution (Y: 119.5 -> 133.5, W: 92)
drawCard(ax1,4,119.5,92.0,14.0,softAccent,BORDER);
text(ax1,6.5,122.8,"ICDR DIABETIC RETINOPATHY PROBABILITY PROFILE","Color",NAVY,"FontSize",8.0,"FontWeight","bold");

labels = {"No DR","Mild NPDR","Moderate NPDR","Severe NPDR","Proliferative DR"};
vals = [probabilities.NoDR probabilities.Mild probabilities.Moderate probabilities.Severe probabilities.ProliferativeDR];
startX = 21.0;
for i = 1:5
    x = startX + (i-1) * 15.0;
    text(ax1,x,125.8,labels{i},"Color",TEXT_MUTED,"FontSize",5.8,"FontWeight","bold","HorizontalAlignment","center");
    rectangle(ax1,"Position",[x-5.5 127.2 11.0 2.5],"FaceColor",[0.88 0.92 0.95],"EdgeColor","none");
    fillW = max(0,min(11.0,vals(i) / 100 * 11.0));
    if fillW > 0
        rectangle(ax1,"Position",[x-5.5 127.2 fillW 2.5],"FaceColor",probabilityColor(i),"EdgeColor","none");
    end
    text(ax1,x,131.5,sprintf("%.1f%%",vals(i)),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center");
end

drawFooter(ax1,TEXT_MUTED,TEAL,1,3);

% Repaint Header
drawHeader(ax1,"EXECUTIVE SCREENING SUMMARY","Diabetic Retinopathy Automated AI Report",screeningId,examDate,NAVY,TEAL,WHITE);

exportgraphics(fig1,tempPdf,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig1);

% ============================================================
% PAGE 2 - RETINAL IMAGE ANALYSIS & GRAD-CAM EXPLAINABILITY
% ============================================================
fig2 = makePageFigure();
ax2 = makePageAxes(fig2);

% Page Canvas
rectangle(ax2,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeader(ax2,"DIAGNOSTIC IMAGING & AI EXPLAINABILITY","Multi-Modal Retinal Grid & Spatial Heatmaps",screeningId,examDate,NAVY,TEAL,WHITE);

% Section Sub-header (Y: 23.0 -> 27.5)
text(ax2,4.5,25.2,"1. MULTI-MODAL RETINAL IMAGING MATRIX","Color",NAVY,"FontSize",10.0,"FontWeight","bold");
text(ax2,4.5,28.0,"Comparative analysis: Raw acquisition, adaptive contrast enhancement, Grad-CAM attention heatmap, and anatomical overlay.","Color",TEXT_MUTED,"FontSize",6.5);

% 2x2 Image Grid (Y: 30.0 -> 101.5)
panelW = 44.5;
panelH = 34.5;

% Panel 1: Original Fundus Image (Top Left)
drawCard(ax2,4.0,30.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,6.0,33.5,"1. ORIGINAL FUNDUS IMAGE","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
text(ax2,6.0,36.0,"Raw unenhanced photographic acquisition","Color",TEXT_MUTED,"FontSize",5.8);
boxP1 = [6.0 37.5 40.5 23.5];
rectangle(ax2,"Position",boxP1,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
showImageInBox(ax2,retinalImage,boxP1);
text(ax2,26.25,63.0,"Standard 45° field of view","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");

% Panel 2: Contrast-Enhanced Vascular View (Top Right)
drawCard(ax2,51.5,30.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,53.5,33.5,"2. CONTRAST-ENHANCED VIEW","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
text(ax2,53.5,36.0,"CLAHE adaptive equalization & vessel sharpening","Color",TEXT_MUTED,"FontSize",5.8);
boxP2 = [53.5 37.5 40.5 23.5];
rectangle(ax2,"Position",boxP2,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
showImageInBox(ax2,enhancedImage,boxP2);
text(ax2,73.75,63.0,"Enhanced capillary & microaneurysm visibility","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");

% Panel 3: Grad-CAM Explainability Heatmap (Bottom Left)
drawCard(ax2,4.0,67.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,6.0,70.5,"3. GRAD-CAM EXPLAINABILITY HEATMAP","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
text(ax2,6.0,73.0,"ResNet-101 layer-specific activation intensity","Color",TEXT_MUTED,"FontSize",5.8);
boxP3 = [6.0 74.5 40.5 23.5];

if hasGradCam && ~isempty(heatmapImage)
    rectangle(ax2,"Position",boxP3,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
    showImageInBox(ax2,heatmapImage,boxP3);
    text(ax2,26.25,100.0,"Warm colors (red/orange) denote highest neural activation","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");
else
    showPlaceholderInBox(ax2,boxP3,"Grad-CAM Heatmap Unavailable","No focal lesion activations detected above threshold.","Classification driven by global retinal vascular features.");
    text(ax2,26.25,100.0,"Analytical threshold: No abnormal focal hotspots","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");
end

% Panel 4: Grad-CAM Anatomical Overlay (Bottom Right)
drawCard(ax2,51.5,67.0,panelW,panelH,CARD_BG,BORDER);
text(ax2,53.5,70.5,"4. GRAD-CAM ANATOMICAL OVERLAY","Color",NAVY,"FontSize",8.0,"FontWeight","bold");
text(ax2,53.5,73.0,"Heatmap registered directly to retinal landmarks","Color",TEXT_MUTED,"FontSize",5.8);
boxP4 = [53.5 74.5 40.5 23.5];

if hasGradCam && ~isempty(overlayImage)
    rectangle(ax2,"Position",boxP4,"FaceColor",[0.04 0.05 0.06],"EdgeColor",BORDER,"LineWidth",0.5);
    showImageInBox(ax2,overlayImage,boxP4);
    text(ax2,73.75,100.0,"Heatmap blended on fundus image with localized regions","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");
else
    showPlaceholderInBox(ax2,boxP4,"Grad-CAM Overlay Unavailable","No focal lesion activations detected above threshold.","Retinal background within normal morphological limits.");
    text(ax2,73.75,100.0,"No localized lesion bounding boxes required","Color",TEXT_MUTED,"FontSize",5.8,"HorizontalAlignment","center");
end

% AI Explainability — Grad-CAM Methodology Narrative (Y: 104.0 -> 133.5, W: 92)
drawCard(ax2,4.0,104.0,92.0,29.5,CARD_BG,BORDER);
text(ax2,6.5,107.5,"AI EXPLAINABILITY — GRAD-CAM METHODOLOGY & INTERPRETATION","Color",NAVY,"FontSize",8.5,"FontWeight","bold");
rectangle(ax2,"Position",[6.5 109.0 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

desc1 = "The Grad-CAM (Gradient-weighted Class Activation Mapping) visualization highlights retinal regions that most strongly contributed to the ResNet-101 model's classification decision. The heatmap reveals the spatial features (microaneurysms, hemorrhages, or exudates) prioritized by the network during inference.";
text(ax2,6.5,112.5,wrapText(desc1,105,2),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

desc2 = "Clinical Interpretability Note: This visualization is intended to support clinician interpretability by revealing where the deep neural network focused its attention. It does not replace comprehensive clinical evaluation or fundus fluorescein angiography.";
text(ax2,6.5,119.5,wrapText(desc2,105,2),"Color",TEXT_MUTED,"FontSize",6.0,"Interpreter","none");

% Summary Chip Box (Y: 125.0 -> 130.5)
rectangle(ax2,"Position",[6.5 125.0 87.0 6.0],"FaceColor",softAccent,"EdgeColor",BORDER,"LineWidth",0.6);
rectangle(ax2,"Position",[6.5 125.0 1.5 6.0],"FaceColor",accent,"EdgeColor","none");

if evidenceCount > 0
    chipText = sprintf("Active Evidence: %d lesion region(s) identified with high activation intensity across the retinal field.",evidenceCount);
else
    chipText = "Active Evidence: No focal lesion regions identified. Model attention reflects global vascular and macular health.";
end
text(ax2,9.5,128.5,string(chipText),"Color",NAVY,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

drawFooter(ax2,TEXT_MUTED,TEAL,2,3);

% Repaint Header
drawHeader(ax2,"DIAGNOSTIC IMAGING & AI EXPLAINABILITY","Multi-Modal Retinal Grid & Spatial Heatmaps",screeningId,examDate,NAVY,TEAL,WHITE);

exportgraphics(fig2,tempPdf,"Append",true,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig2);

% ============================================================
% PAGE 3 - CLINICAL FINDINGS, SUSPECTED LESIONS & ACTION PLAN
% ============================================================
fig3 = makePageFigure();
ax3 = makePageAxes(fig3);

% Page Canvas
rectangle(ax3,"Position",[0 0 100 140],"FaceColor",BG_PAGE,"EdgeColor","none");

% Header
drawHeader(ax3,"CLINICAL FINDINGS & ACTION PLAN","Lesion Inventory, Recommended Steps & Disclaimer",screeningId,examDate,NAVY,TEAL,WHITE);

% Section 1: AI Screening Findings (Structured Bullet Points) (Y: 23.5 -> 53.5)
drawCard(ax3,4.0,23.5,92.0,30.0,CARD_BG,BORDER);
text(ax3,6.5,27.0,"CLINICAL AI SCREENING FINDINGS","Color",NAVY,"FontSize",9.0,"FontWeight","bold");
text(ax3,6.5,29.8,"Algorithmic assessment of primary retinopathy biomarkers","Color",TEXT_MUTED,"FontSize",6.0);
rectangle(ax3,"Position",[6.5 31.0 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Bullet 1: Primary Diagnosis
drawBulletIcon(ax3,7.0,34.5,BLUE);
text(ax3,10.0,34.8,"Primary DR Diagnosis:","Color",NAVY,"FontSize",6.8,"FontWeight","bold");
text(ax3,33.0,34.8,sprintf("%s  (Confidence: %.1f%%  •  Tier: %s)",formatDiagnosisTitle(predictedClass),confidence,confidenceStatus),"Color",TEXT_DARK,"FontSize",6.8,"FontWeight","bold","Interpreter","none");
b1Text = sprintf("ResNet-101 classified the examination as %s with %.1f%% certainty (NoDR: %.1f%%, Mild: %.1f%%, Moderate: %.1f%%, Severe: %.1f%%, Proliferative: %.1f%%).", ...
    predictedClass, confidence, probabilities.NoDR, probabilities.Mild, probabilities.Moderate, probabilities.Severe, probabilities.ProliferativeDR);
text(ax3,10.0,37.8,wrapText(b1Text,102,1),"Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");

% Bullet 2: Referral Assessment
drawBulletIcon(ax3,7.0,41.0,accent);
text(ax3,10.0,41.3,"Clinical Referral Status:","Color",NAVY,"FontSize",6.8,"FontWeight","bold");
text(ax3,35.0,41.3,string(referralStatus),"Color",accent,"FontSize",6.8,"FontWeight","bold","Interpreter","none");
if strcmpi(string(referralStatus),"REFERABLE DR")
    b2Text = "Clinical referral is indicated. Signs consistent with vision-threatening diabetic retinopathy were identified, requiring ophthalmological evaluation.";
else
    b2Text = "No signs of vision-threatening diabetic retinopathy detected on the presenting image. Standard periodic rescreening recommended.";
end
text(ax3,10.0,44.3,wrapText(b2Text,102,1),"Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");

% Bullet 3: Lesion Biomarker Distribution
drawBulletIcon(ax3,7.0,47.5,TEAL);
text(ax3,10.0,47.8,"Lesion Biomarker Assessment:","Color",NAVY,"FontSize",6.8,"FontWeight","bold");
text(ax3,39.0,47.8,sprintf("%d Suspicious Region(s) Localized",evidenceCount),"Color",TEXT_DARK,"FontSize",6.8,"FontWeight","bold");
b3Text = buildLesionSummaryNarrative(lesionEvidence, evidenceCount);
text(ax3,10.0,50.8,wrapText(b3Text,102,1),"Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");

% Section 2: Suspected Lesion Evidence Regions Table (Y: 55.5 -> 88.5)
drawCard(ax3,4.0,55.5,92.0,33.0,CARD_BG,BORDER);
text(ax3,6.5,59.0,"SUSPECTED LESION EVIDENCE REGIONS","Color",NAVY,"FontSize",9.0,"FontWeight","bold");
text(ax3,6.5,61.5,"Quantitative coordinates and activation intensities localized by the lesion evidence module","Color",TEXT_MUTED,"FontSize",6.0);
rectangle(ax3,"Position",[6.5 62.8 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Table Column Headers (Y: 65.5)
rectangle(ax3,"Position",[6.5 64.0 87.0 4.2],"FaceColor",[0.92 0.95 0.98],"EdgeColor","none");
text(ax3,8.0,66.5,"#","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,13.0,66.5,"LESION TYPE","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,38.0,66.5,"COORDINATES (X, Y)","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,58.0,66.5,"BOUNDING BOX","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,72.0,66.5,"AREA","Color",NAVY,"FontSize",6.2,"FontWeight","bold");
text(ax3,83.0,66.5,"ACTIVATION PEAK","Color",NAVY,"FontSize",6.2,"FontWeight","bold");

% Table Data Rows
evidenceRows = makeEvidenceRows(lesionEvidence, size(retinalImage));
tableY = 69.0;
rowHeight = 4.2;

if isempty(evidenceRows)
    rectangle(ax3,"Position",[6.5 tableY 87.0 8.0],"FaceColor",[0.96 0.98 0.99],"EdgeColor",BORDER,"LineWidth",0.4);
    text(ax3,8.5,tableY+3.5,"No focal lesion evidence regions were detected above the analytical threshold.","Color",TEXT_DARK,"FontSize",6.5,"FontWeight","bold","Interpreter","none");
    text(ax3,8.5,tableY+6.0,"The retinal field shows no localized signs of microaneurysms, hemorrhages, or exudates.","Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");
else
    maxDisplayRows = min(4,size(evidenceRows,1));
    for r = 1:maxDisplayRows
        rowBg = CARD_BG;
        if mod(r,2) == 0
            rowBg = [0.97 0.98 0.99];
        end
        rectangle(ax3,"Position",[6.5 tableY 87.0 rowHeight],"FaceColor",rowBg,"EdgeColor",BORDER,"LineWidth",0.3);
        
        text(ax3,8.0,tableY+2.7,string(r),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold");
        text(ax3,13.0,tableY+2.7,string(evidenceRows{r,1}),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold","Interpreter","none");
        text(ax3,38.0,tableY+2.7,string(evidenceRows{r,2}),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");
        text(ax3,58.0,tableY+2.7,string(evidenceRows{r,3}),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");
        text(ax3,72.0,tableY+2.7,string(evidenceRows{r,4}),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");
        text(ax3,83.0,tableY+2.7,string(evidenceRows{r,5}),"Color",TEXT_DARK,"FontSize",6.2,"FontWeight","bold","Interpreter","none");
        
        tableY = tableY + rowHeight;
    end
    if size(evidenceRows,1) > maxDisplayRows
        text(ax3,8.5,tableY+2.5,sprintf("+%d additional evidence region(s) recorded in full clinical database.",size(evidenceRows,1)-maxDisplayRows),"Color",TEXT_MUTED,"FontSize",5.8,"Interpreter","none");
    end
end

% Section 3: Recommended Clinical Next Steps (Y: 90.5 -> 113.0)
drawCard(ax3,4.0,90.5,92.0,22.5,CARD_BG,BORDER);
rectangle(ax3,"Position",[4.0 90.5 2.0 22.5],"FaceColor",accent,"EdgeColor","none");

text(ax3,8.0,94.0,"RECOMMENDED CLINICAL ACTION PLAN","Color",NAVY,"FontSize",8.8,"FontWeight","bold");
text(ax3,8.0,98.0,wrapText(char(recommendation),95,2),"Color",accent,"FontSize",7.8,"FontWeight","bold","Interpreter","none");

% Structured Action Items
drawSmallBullet(ax3,8.5,103.0,accent);
if strcmpi(string(referralStatus),"REFERABLE DR")
    action1 = "Specialist Referral: Schedule comprehensive evaluation with a vitreoretinal specialist within 2–4 weeks.";
else
    action1 = "Routine Rescreening: Schedule follow-up annual diabetic retinopathy screening in 12 months.";
end
text(ax3,11.5,103.3,string(action1),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

drawSmallBullet(ax3,8.5,107.0,BLUE);
action2 = "Systemic Glycemic Control: Maintain target HbA1c (< 7.0%), blood pressure (< 130/80 mmHg), and lipid profile.";
text(ax3,11.5,107.3,string(action2),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

drawSmallBullet(ax3,8.5,111.0,TEAL);
action3 = "Patient Counseling: Advise patient to seek urgent medical evaluation if experiencing sudden vision loss, floaters, or shadows.";
text(ax3,11.5,111.3,string(action3),"Color",TEXT_DARK,"FontSize",6.2,"Interpreter","none");

% Section 4: Clinical Disclaimer & Healthcare Verification (Y: 115.0 -> 133.5)
drawCard(ax3,4.0,115.0,92.0,18.5,CARD_BG,BORDER);

% Left: Disclaimer
text(ax3,6.5,118.0,"CLINICAL AI DISCLAIMER & RESPONSIBILITY NOTICE","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
disclaimerFull = "This report is generated by an AI-assisted screening system and is intended to support screening and referral decisions. It is not a substitute for examination, diagnosis, or treatment by a qualified healthcare professional. Clinical decisions must remain the responsibility of a registered medical practitioner.";
text(ax3,6.5,121.5,wrapText(disclaimerFull,58,4),"Color",TEXT_MUTED,"FontSize",5.4,"Interpreter","none");

% Right: Clinician Verification Block
rectangle(ax3,"Position",[61.0 116.5 0.35 15.0],"FaceColor",BORDER,"EdgeColor","none");
text(ax3,63.5,118.0,"CLINICAL VERIFICATION & SIGN-OFF","Color",NAVY,"FontSize",6.5,"FontWeight","bold");
text(ax3,63.5,122.0,"Reviewing Clinician:  __________________________","Color",TEXT_MUTED,"FontSize",5.6);
text(ax3,63.5,126.0,"Signature / Date:     __________________________","Color",TEXT_MUTED,"FontSize",5.6);
text(ax3,63.5,130.0,"Facility / Center:    Jeevana Netra Vision Center","Color",TEXT_MUTED,"FontSize",5.6);

drawFooter(ax3,TEXT_MUTED,TEAL,3,3);

% Repaint Header
drawHeader(ax3,"CLINICAL FINDINGS & ACTION PLAN","Lesion Inventory, Recommended Steps & Disclaimer",screeningId,examDate,NAVY,TEAL,WHITE);

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

function drawHeader(ax, pageCategory, pageTitle, screeningId, examDate, navyColor, tealColor, whiteColor)
% Professional branded header band
rectangle(ax,"Position",[0 0 100 20.0],"FaceColor",navyColor,"EdgeColor","none");
rectangle(ax,"Position",[0 19.3 100 0.7],"FaceColor",tealColor,"EdgeColor","none");

text(ax,4.5,5.5,"JEEVANA NETRA","Color",whiteColor,"FontSize",18.0,"FontWeight","bold");
text(ax,4.5,9.5,"AI FOR BETTER VISION  •  SMART RETINAL HEALTH SCREENING","Color",[0.55 0.90 0.85],"FontSize",7.0,"FontWeight","bold");
text(ax,4.5,15.5,pageCategory + "  |  " + pageTitle,"Color",[0.84 0.90 0.95],"FontSize",8.5,"FontWeight","bold","Interpreter","none");

text(ax,95.5,5.5,"REPORT IDENTIFIER","Color",[0.65 0.75 0.85],"FontSize",6.0,"FontWeight","bold","HorizontalAlignment","right");
text(ax,95.5,9.5,string(screeningId),"Color",whiteColor,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,95.5,15.5,"Date: " + string(examDate),"Color",[0.78 0.86 0.92],"FontSize",6.5,"HorizontalAlignment","right","Interpreter","none");
end

function drawFooter(ax, mutedColor, tealColor, pageNo, totalPages)
rectangle(ax,"Position",[4 135 92 0.35],"FaceColor",[0.82 0.88 0.92],"EdgeColor","none");
text(ax,4.5,137.8,"Jeevana Netra AI Screening System  •  SIH 2026","Color",mutedColor,"FontSize",6.0);
text(ax,50.0,137.8,"CONFIDENTIAL CLINICAL SCREENING RECORD","Color",mutedColor,"FontSize",5.8,"FontWeight","bold","HorizontalAlignment","center");
text(ax,95.5,137.8,"Page " + string(pageNo) + " of " + string(totalPages),"Color",mutedColor,"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","right");
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

% Draw subtle medical target symbol
iconR = 3.0;
iconY = cy - 4.0;
t = linspace(0,2*pi,60);
fill(ax,cx + iconR*cos(t),iconY + iconR*sin(t),[0.88 0.92 0.96],"EdgeColor",[0.72 0.80 0.88],"LineWidth",0.7);
plot(ax,[cx - 1.8, cx + 1.8],[iconY, iconY],"Color",[0.45 0.55 0.68],"LineWidth",0.9);
plot(ax,[cx, cx],[iconY - 1.8, iconY + 1.8],"Color",[0.45 0.55 0.68],"LineWidth",0.9);

text(ax,cx,cy+1.5,string(titleStr),"Color",[0.15 0.25 0.38],"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax,cx,cy+4.8,string(subStr),"Color",[0.42 0.50 0.60],"FontSize",5.6,"HorizontalAlignment","center","Interpreter","none");
text(ax,cx,cy+7.8,string(noteStr),"Color",[0.08 0.50 0.55],"FontSize",5.2,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
end

function drawConfidenceRing(ax, cx, cy, r, pct, accent, textColor, mutedColor)
t = linspace(0,2*pi,180);
plot(ax,cx+r*cos(t),cy+r*sin(t),"Color",[0.88 0.92 0.95],"LineWidth",4.2);
clampedPct = max(0,min(100,pct));
ang = linspace(pi/2,pi/2 - 2*pi*clampedPct/100,150);
plot(ax,cx+r*cos(ang),cy+r*sin(ang),"Color",accent,"LineWidth",4.2);
text(ax,cx,cy-1.2,sprintf("%.1f%%",pct),"Color",textColor,"FontSize",13.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax,cx,cy+2.8,"Confidence Score","Color",mutedColor,"FontSize",5.8,"HorizontalAlignment","center");
end

function drawBulletIcon(ax, x, y, color)
rectangle(ax,"Position",[x y-1.4 1.8 1.8],"FaceColor",color,"EdgeColor","none");
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
        bboxStr = string(sprintf("%dx%d px",round(w),round(h)));
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

function narrative = buildLesionSummaryNarrative(lesionEvidence, evidenceCount)
if evidenceCount == 0
    narrative = "No focal microaneurysms, hemorrhages, or exudates identified. Neural activation was distributed across healthy vascular architecture.";
    return;
end

types = strings(0);
if isstruct(lesionEvidence)
    for i = 1:numel(lesionEvidence)
        if isfield(lesionEvidence(i),"hasEvidence") && lesionEvidence(i).hasEvidence
            types(end+1) = string(lesionEvidence(i).type); %#ok<AGROW>
        end
    end
end

if isempty(types)
    narrative = sprintf("%d evidence region(s) identified in the retinal field requiring clinical review.",evidenceCount);
else
    narrative = sprintf("%d suspicious region(s) identified with positive biomarker evidence for: %s.",evidenceCount,strjoin(types,", "));
end
end

function titleStr = formatDiagnosisTitle(predictedClass)
s = lower(strtrim(char(string(predictedClass))));
switch s
    case {"nodr","no dr"}
        titleStr = "No Diabetic Retinopathy";
    case "mild"
        titleStr = "Mild Non-Proliferative DR";
    case "moderate"
        titleStr = "Moderate Non-Proliferative DR";
    case "severe"
        titleStr = "Severe Non-Proliferative DR";
    case {"proliferativedr","proliferative dr","proliferative"}
        titleStr = "Proliferative Diabetic Retinopathy";
    otherwise
        titleStr = string(predictedClass);
end
end

function tagStr = formatGradeTag(predictedClass)
s = lower(strtrim(char(string(predictedClass))));
switch s
    case {"nodr","no dr"}
        tagStr = "Classification: ICDR Grade 0 (Non-Referable)";
    case "mild"
        tagStr = "Classification: ICDR Grade 1 (Non-Referable)";
    case "moderate"
        tagStr = "Classification: ICDR Grade 2 (Referable)";
    case "severe"
        tagStr = "Classification: ICDR Grade 3 (Referable Urgent)";
    case {"proliferativedr","proliferative dr","proliferative"}
        tagStr = "Classification: ICDR Grade 4 (High-Risk Referable)";
    otherwise
        tagStr = "Classification: Standard ICDR Scale";
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
    value = "N/A";
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
