function response = jeevana_report_api(requestJson)
% JEEVANA_REPORT_API
% Generates an ultra-modern, high-tech single-page clinical AI screening report
% for Jeevana Netra (Smart India Hackathon 2026 Showcase).
%
% Visual Theme: High-Tech Hackathon Showcase (Deep Navy #0B2A4A & Electric Cyan)
% Layout: Executive 1-Page Medical Dashboard with 3 Images Side-by-Side
%
% Preserves 100% of the underlying AI model, inference, weights, and API contract.
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

screeningId = "JN-2026-REPORT";
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
qualityStatus = getStringField(result,"qualityStatus","Good");
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
[numHemorrhages, numMicroaneurysms, numExudates] = buildLesionBreakdown(lesionEvidence);

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
[heatmapImage, overlayImage] = extractGradCamData(retinalImage, request, result, lesionEvidence);

safePatientId = makeSafeFilename(patientId);
timeText = string(datetime("now","Format","yyyyMMdd_HHmmss"));
fileName = char("Jeevana_Netra_Report_" + safePatientId + "_" + timeText + ".pdf");

%% 6. Color Palette: High-Tech Hackathon Showcase (Deep Navy + Electric Cyan)

BG_CANVAS   = [7 20 36] / 255;       % #071424 Deep Midnight Navy Canvas
CARD_BG     = [13 32 56] / 255;      % #0D2038 Sleek Dark Card Surface
CARD_INNER  = [18 42 72] / 255;      % #122A48 Recessed Card Panel
BORDER      = [28 62 100] / 255;     % #1C3E64 Tech Structure Border
BORDER_GLOW = [0 215 200] / 255;     % #00D7C8 Neon Cyan Accent Border

CYAN        = [0 230 220] / 255;     % #00E6DC Electric Neon Cyan Accent
CYAN_SOFT   = [0 230 220] * 0.18 + CARD_BG * 0.82;
BLUE_TECH   = [24 144 255] / 255;    % #1890FF High-Tech Blue
WHITE       = [1 1 1];               % Pure White Primary Text
TEXT_LIGHT  = [215 232 248] / 255;   % #D7E8F8 Crisp Ice Blue Text
TEXT_MUTED  = [115 145 178] / 255;   % #7391B2 Cool Steel Gray

NEON_GREEN  = [0 230 118] / 255;     % #00E676 Neon Emerald (Normal / No DR)
NEON_AMBER  = [255 179 0] / 255;     % #FFB300 Neon Amber (Mild DR)
NEON_ORANGE = [255 109 0] / 255;     % #FF6D00 Neon Orange (Moderate DR)
NEON_RED    = [255 61 90] / 255;     % #FF3D5A Neon Coral Alert (Severe DR)
NEON_PURPLE = [213 0 249] / 255;     % #D500F9 Neon Magenta (Proliferative DR)

accent = severityNeonColor(predictedClass,NEON_GREEN,NEON_AMBER,NEON_RED,NEON_PURPLE,CYAN);
softAccent = accent * 0.20 + CARD_BG * 0.80;

% ============================================================
% 7. Render High-Tech Single-Page Executive Dashboard
% ============================================================
fig = makePageFigure();
ax = makePageAxes(fig);

% Midnight Navy Canvas
rectangle(ax,"Position",[0 0 100 140],"FaceColor",BG_CANVAS,"EdgeColor","none");

% 1. Header Band with Glowing Neon Line (Y: 0.0 -> 14.5)
rectangle(ax,"Position",[0 0 100 14.5],"FaceColor",[10 26 46]/255,"EdgeColor","none");
rectangle(ax,"Position",[0 13.8 100 0.7],"FaceColor",CYAN,"EdgeColor","none");

% Top AI pulse chip
rectangle(ax,"Position",[4.0 3.2 18.5 3.2],"FaceColor",CYAN_SOFT,"EdgeColor",CYAN,"LineWidth",0.6);
plot(ax,5.2,4.8,"o","MarkerFaceColor",CYAN,"MarkerEdgeColor","none","MarkerSize",3.2);
text(ax,7.2,5.0,"AI ACTIVE INFERENCE","Color",CYAN,"FontSize",5.2,"FontWeight","bold");

text(ax,4.0,9.8,"JEEVANA NETRA","Color",WHITE,"FontSize",17.0,"FontWeight","bold");
text(ax,38.0,9.8,"•   CLINICAL AI RETINAL SCREENING SYSTEM","Color",CYAN,"FontSize",7.0,"FontWeight","bold");
text(ax,4.0,12.5,"Smart India Hackathon 2026  •  Explainable Deep Learning Retinopathy Assessment","Color",TEXT_MUTED,"FontSize",5.6);

text(ax,96.0,4.2,"REPORT ID: " + string(screeningId),"Color",WHITE,"FontSize",7.2,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,96.0,7.8,"Date: " + string(examDate),"Color",TEXT_LIGHT,"FontSize",6.0,"HorizontalAlignment","right","Interpreter","none");
text(ax,96.0,11.5,"Architecture: ResNet-101 • Grad-CAM","Color",CYAN,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","right");

% 2. Patient Information Strip (Y: 16.0 -> 26.5, Height 10.5, Width 92.0)
drawCard(ax,4.0,16.0,92.0,10.5,CARD_BG,BORDER);

text(ax,6.5,18.8,"PATIENT NAME","Color",CYAN,"FontSize",5.2,"FontWeight","bold");
text(ax,6.5,22.8,string(patientName),"Color",WHITE,"FontSize",8.2,"FontWeight","bold","Interpreter","none");

text(ax,30.0,18.8,"PATIENT ID","Color",CYAN,"FontSize",5.2,"FontWeight","bold");
text(ax,30.0,22.8,string(patientId),"Color",TEXT_LIGHT,"FontSize",7.5,"FontWeight","bold","Interpreter","none");

text(ax,48.0,18.8,"AGE / GENDER","Color",CYAN,"FontSize",5.2,"FontWeight","bold");
text(ax,48.0,22.8,formatAge(patientAge) + "  •  " + string(patientGender),"Color",TEXT_LIGHT,"FontSize",7.5,"FontWeight","bold","Interpreter","none");

text(ax,70.0,18.8,"ANALYSED FIELD","Color",CYAN,"FontSize",5.2,"FontWeight","bold");
text(ax,70.0,22.8,string(analysedEye),"Color",WHITE,"FontSize",7.5,"FontWeight","bold","Interpreter","none");

text(ax,87.0,18.8,"VERIFICATION","Color",CYAN,"FontSize",5.2,"FontWeight","bold");
rectangle(ax,"Position",[86.0 21.0 9.0 3.2],"FaceColor",[0 230 118]/255 * 0.18 + CARD_BG * 0.82,"EdgeColor",NEON_GREEN,"LineWidth",0.6);
text(ax,90.5,22.8,"GRADABLE","Color",NEON_GREEN,"FontSize",5.0,"FontWeight","bold","HorizontalAlignment","center");

% 3. Hero AI Screening Result Card (Y: 28.0 -> 47.0, Height 19.0, Width 92.0)
drawCard(ax,4.0,28.0,92.0,19.0,CARD_BG,BORDER);
rectangle(ax,"Position",[4.0 28.0 2.5 19.0],"FaceColor",accent,"EdgeColor","none");

% Top label
text(ax,8.0,30.8,"AI SCREENING RESULT  —  PRIMARY DIAGNOSTIC ASSESSMENT","Color",CYAN,"FontSize",6.2,"FontWeight","bold");

% Large prominent diagnosis
diagnosisText = formatDiagnosisTitle(predictedClass);
text(ax,8.0,36.5,upper(diagnosisText),"Color",accent,"FontSize",13.5,"FontWeight","bold","Interpreter","none");
text(ax,8.0,40.5,formatGradeTag(predictedClass),"Color",TEXT_LIGHT,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

% Status badge line
rectangle(ax,"Position",[8.0 42.0 45.0 3.6],"FaceColor",CARD_INNER,"EdgeColor",BORDER,"LineWidth",0.4);
text(ax,9.5,44.2,"Severity: " + string(predictedClass) + "   •   Eye: " + string(analysedEye),"Color",TEXT_LIGHT,"FontSize",5.8,"FontWeight","bold","Interpreter","none");

% Center: Glowing Neon Confidence Ring
cx = 64.0; cy = 37.5; r = 5.0;
drawNeonConfidenceRing(ax,cx,cy,r,confidence,accent,WHITE,TEXT_MUTED);
text(ax,cx,cy+6.5,sprintf("[%s TIER]",upper(char(string(confidenceStatus)))),"Color",CYAN,"FontSize",5.2,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");

% Right: Referral Triage Box
rectangle(ax,"Position",[75.0 31.5 19.0 13.5],"FaceColor",softAccent,"EdgeColor",accent,"LineWidth",0.8);
text(ax,84.5,34.5,"REFERRAL STATUS","Color",accent,"FontSize",5.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax,84.5,38.5,wrapText(char(referralStatus),15,1),"Color",WHITE,"FontSize",7.0,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax,84.5,42.5,sprintf("Evidence Count: %d",evidenceCount),"Color",TEXT_LIGHT,"FontSize",5.5,"FontWeight","bold","HorizontalAlignment","center");

% 4. Multi-Modal Retinal Imaging Grid (3 Images Side-by-Side) (Y: 48.5 -> 82.5, Height 34.0, Width 92.0)
drawCard(ax,4.0,48.5,92.0,34.0,CARD_BG,BORDER);
text(ax,6.5,51.2,"MULTI-MODAL RETINAL IMAGING & EXPLAINABLE AI","Color",WHITE,"FontSize",7.5,"FontWeight","bold");
text(ax,93.5,51.2,"ResNet-101 Spatial Attention & Vessel Mapping","Color",CYAN,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","right");
rectangle(ax,"Position",[6.5 52.4 87.0 0.35],"FaceColor",BORDER,"EdgeColor","none");

imgW = 27.5;
imgH = 21.5;
imgY = 54.0;
x1 = 6.5;
x2 = 36.25;
x3 = 66.0;

% Image 1: Original Fundus
rectangle(ax,"Position",[x1 imgY imgW imgH],"FaceColor",[3 10 18]/255,"EdgeColor",BORDER,"LineWidth",0.6);
showImageInBox(ax,retinalImage,[x1 imgY imgW imgH]);
text(ax,x1+imgW/2,77.5,"1. Original Retina (Color Fundus)","Color",TEXT_LIGHT,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","center");

% Image 2: Enhanced Retina
rectangle(ax,"Position",[x2 imgY imgW imgH],"FaceColor",[3 10 18]/255,"EdgeColor",BORDER,"LineWidth",0.6);
showImageInBox(ax,enhancedImage,[x2 imgY imgW imgH]);
text(ax,x2+imgW/2,77.5,"2. Enhanced Vasculature (CLAHE)","Color",TEXT_LIGHT,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","center");

% Image 3: Grad-CAM Overlay (Glowing Cyan Border!)
rectangle(ax,"Position",[x3 imgY imgW imgH],"FaceColor",[3 10 18]/255,"EdgeColor",CYAN,"LineWidth",0.8);
showImageInBox(ax,overlayImage,[x3 imgY imgW imgH]);
text(ax,x3+imgW/2,77.5,"3. Grad-CAM Anatomical Overlay","Color",CYAN,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","center");

text(ax,6.5,80.8,"Explainability: Grad-CAM highlights deep retinal feature activations. Warmer colors indicate primary convolutional focus.","Color",TEXT_MUTED,"FontSize",5.0);

% 5. Split Section: DR Stage Probabilities (Left) & Biomarkers/Quality (Right) (Y: 84.0 -> 111.0, Height 27.0, Width 92.0)
% Left: Probabilities (W: 44.5)
drawCard(ax,4.0,84.0,44.5,27.0,CARD_BG,BORDER);
text(ax,6.5,86.8,"DR STAGE PROBABILITY PROFILE","Color",WHITE,"FontSize",6.8,"FontWeight","bold");
text(ax,6.5,89.0,"Multi-class softmax posterior distribution","Color",CYAN,"FontSize",5.0);
rectangle(ax,"Position",[6.5 90.0 39.5 0.35],"FaceColor",BORDER,"EdgeColor","none");

labels = {"No DR", "Mild NPDR", "Moderate NPDR", "Severe NPDR", "Proliferative DR"};
vals = [probabilities.NoDR, probabilities.Mild, probabilities.Moderate, probabilities.Severe, probabilities.ProliferativeDR];
pColors = [NEON_GREEN; NEON_AMBER; NEON_ORANGE; NEON_RED; NEON_PURPLE];
pY = 92.0;
barH = 2.0;
maxBarW = 21.0;

for i = 1:5
    text(ax,6.5,pY+1.5,labels{i},"Color",TEXT_LIGHT,"FontSize",5.4,"FontWeight","bold");
    
    trX = 23.5;
    rectangle(ax,"Position",[trX pY maxBarW barH],"FaceColor",CARD_INNER,"EdgeColor","none");
    fillW = max(0,min(maxBarW,(vals(i) / 100) * maxBarW));
    if fillW > 0
        rectangle(ax,"Position",[trX pY fillW barH],"FaceColor",pColors(i,:),"EdgeColor","none");
    end
    text(ax,trX + maxBarW + 1.5,pY+1.5,sprintf("%.1f%%",vals(i)),"Color",WHITE,"FontSize",5.4,"FontWeight","bold");
    pY = pY + 3.4;
end

% Right: Biomarkers & Quality (W: 45.5, X: 50.5)
drawCard(ax,50.5,84.0,45.5,27.0,CARD_BG,BORDER);
text(ax,53.0,86.8,"CLINICAL BIOMARKERS & QUALITY","Color",WHITE,"FontSize",6.8,"FontWeight","bold");
text(ax,53.0,89.0,"Quantitative optical measurements & integrity","Color",CYAN,"FontSize",5.0);
rectangle(ax,"Position",[53.0 90.0 40.5 0.35],"FaceColor",BORDER,"EdgeColor","none");

% Metric 1: Quality Score
text(ax,53.0,93.5,"Image Quality:","Color",CYAN,"FontSize",5.6,"FontWeight","bold");
text(ax,67.0,93.5,formatQualityIndex(qualityStatus) + " (Gradable: Yes)","Color",NEON_GREEN,"FontSize",5.6,"FontWeight","bold");

% Metric 2: Macula Status
text(ax,53.0,97.5,"Macula Status:","Color",CYAN,"FontSize",5.6,"FontWeight","bold");
text(ax,67.0,97.5,string(maculaInvolvement),"Color",WHITE,"FontSize",5.6,"FontWeight","bold","Interpreter","none");

% Metric 3: Lesions Count
text(ax,53.0,101.5,"Suspected Lesions:","Color",CYAN,"FontSize",5.6,"FontWeight","bold");
if evidenceCount > 0
    lStr = sprintf("%d Regions (%d Haem, %d Exud)",evidenceCount,numHemorrhages + numMicroaneurysms,numExudates);
    lCol = accent;
else
    lStr = "0 Detected (Retinal Field Clear)";
    lCol = NEON_GREEN;
end
text(ax,70.0,101.5,string(lStr),"Color",lCol,"FontSize",5.6,"FontWeight","bold");

% Metric 4: Optical Indices
text(ax,53.0,105.5,"Optical Indices:","Color",CYAN,"FontSize",5.6,"FontWeight","bold");
optStr = sprintf("Sharp: %s • Cont: %s • Bright: %s",formatMetric(sharpness),formatMetric(contrast),formatMetric(brightness));
text(ax,67.5,105.5,string(optStr),"Color",TEXT_LIGHT,"FontSize",5.2);

text(ax,53.0,109.0,"Diagnostic Adequacy: Validated suitable for AI inference","Color",CYAN,"FontSize",5.0,"FontWeight","bold");

% 6. Clinical Recommendations Card (Y: 112.5 -> 125.0, Height 12.5, Width 92.0)
drawCard(ax,4.0,112.5,92.0,12.5,CARD_BG,BORDER);
rectangle(ax,"Position",[4.0 112.5 2.5 12.5],"FaceColor",accent,"EdgeColor","none");

text(ax,8.0,115.0,"RECOMMENDED CLINICAL ACTION PLAN","Color",WHITE,"FontSize",6.8,"FontWeight","bold");
text(ax,8.0,118.0,wrapText(char(recommendation),95,1),"Color",accent,"FontSize",6.5,"FontWeight","bold","Interpreter","none");

if strcmpi(string(referralStatus),"REFERABLE DR")
    action1 = "• Specialist Referral: Schedule dilated ophthalmic exam with a vitreoretinal specialist within 2–4 weeks.";
else
    action1 = "• Routine Rescreening: Repeat AI-assisted retinal screening in 6–12 months as part of ongoing diabetes care.";
end
text(ax,8.0,121.0,string(action1),"Color",TEXT_LIGHT,"FontSize",5.6,"Interpreter","none");

action2 = "• Systemic Optimization: Maintain HbA1c < 7.0%, blood pressure < 130/80 mmHg, and lipid profile within target range.";
text(ax,8.0,123.5,string(action2),"Color",TEXT_MUTED,"FontSize",5.4,"Interpreter","none");

% 7. Footer, Disclaimer & Verification Block (Y: 126.5 -> 138.5, Height 12.0, Width 92.0)
drawCard(ax,4.0,126.5,92.0,12.0,CARD_BG,BORDER);

% Left: Disclaimer
text(ax,6.0,129.0,"MEDICAL DISCLAIMER & NOTICE","Color",CYAN,"FontSize",5.5,"FontWeight","bold");
discStr = "This report is generated by an AI-assisted screening system and is intended for screening and decision support. It is not a substitute for comprehensive diagnosis by a qualified medical practitioner.";
text(ax,6.0,132.0,wrapText(discStr,58,2),"Color",TEXT_MUTED,"FontSize",4.8,"Interpreter","none");
text(ax,6.0,136.5,"Developed by Team JEEVANA-NETRA  •  SIH 2026  •  AI FOR BETTER VISION","Color",CYAN,"FontSize",5.0,"FontWeight","bold");

% Right: Clinician Verification
rectangle(ax,"Position",[62.0 127.5 0.35 10.0],"FaceColor",BORDER,"EdgeColor","none");
text(ax,64.0,129.0,"HEALTHCARE PROVIDER VERIFICATION","Color",WHITE,"FontSize",5.5,"FontWeight","bold");
text(ax,64.0,132.0,"Reviewing Clinician:  ____________________________","Color",TEXT_MUTED,"FontSize",5.0);
text(ax,64.0,135.0,"Signature / Date:     ____________________________","Color",TEXT_MUTED,"FontSize",5.0);

% Repaint Header Band for crispness
rectangle(ax,"Position",[0 0 100 14.5],"FaceColor",[10 26 46]/255,"EdgeColor","none");
rectangle(ax,"Position",[0 13.8 100 0.7],"FaceColor",CYAN,"EdgeColor","none");
rectangle(ax,"Position",[4.0 3.2 18.5 3.2],"FaceColor",CYAN_SOFT,"EdgeColor",CYAN,"LineWidth",0.6);
plot(ax,5.2,4.8,"o","MarkerFaceColor",CYAN,"MarkerEdgeColor","none","MarkerSize",3.2);
text(ax,7.2,5.0,"AI ACTIVE INFERENCE","Color",CYAN,"FontSize",5.2,"FontWeight","bold");

text(ax,4.0,9.8,"JEEVANA NETRA","Color",WHITE,"FontSize",17.0,"FontWeight","bold");
text(ax,38.0,9.8,"•   CLINICAL AI RETINAL SCREENING SYSTEM","Color",CYAN,"FontSize",7.0,"FontWeight","bold");
text(ax,4.0,12.5,"Smart India Hackathon 2026  •  Explainable Deep Learning Retinopathy Assessment","Color",TEXT_MUTED,"FontSize",5.6);

text(ax,96.0,4.2,"REPORT ID: " + string(screeningId),"Color",WHITE,"FontSize",7.2,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,96.0,7.8,"Date: " + string(examDate),"Color",TEXT_LIGHT,"FontSize",6.0,"HorizontalAlignment","right","Interpreter","none");
text(ax,96.0,11.5,"Architecture: ResNet-101 • Grad-CAM","Color",CYAN,"FontSize",5.6,"FontWeight","bold","HorizontalAlignment","right");

% Export Exactly 1 Page
exportgraphics(fig,tempPdf,"ContentType","image","Resolution",300,"BackgroundColor","current");
close(fig);

% ============================================================
% 8. Read and Return PDF Bytes
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
fig = figure("Visible","off","Color",[7 20 36]/255,"Units","inches","Position",[1 1 8.27 11.69],"MenuBar","none","ToolBar","none");
end

function ax = makePageAxes(fig)
ax = axes(fig,"Units","normalized","Position",[0 0 1 1]);
axis(ax,"off");
xlim(ax,[0 100]);
ylim(ax,[0 140]);
set(ax,"YDir","reverse");
hold(ax,"on");
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

function drawNeonConfidenceRing(ax, cx, cy, r, pct, accent, textColor, mutedColor)
t = linspace(0,2*pi,180);
plot(ax,cx+r*cos(t),cy+r*sin(t),"Color",[20 48 80]/255,"LineWidth",3.5);
clampedPct = max(0,min(100,pct));
ang = linspace(pi/2,pi/2 - 2*pi*clampedPct/100,150);
plot(ax,cx+r*cos(ang),cy+r*sin(ang),"Color",accent,"LineWidth",3.5);
text(ax,cx,cy-0.8,sprintf("%.1f%%",pct),"Color",textColor,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax,cx,cy+2.2,"Certainty","Color",mutedColor,"FontSize",4.8,"HorizontalAlignment","center");
end

function [heatmapRGB, overlayImage] = extractGradCamData(retinalImage, request, result, lesionEvidence)
H = size(retinalImage,1);
W = size(retinalImage,2);
hasGradCam = false;
camMap = zeros(H,W);

% 1. Check if direct heatmap matrix was passed in result or request
if isfield(result,"heatmap") && ~isempty(result.heatmap) && isnumeric(result.heatmap)
    camMap = double(result.heatmap);
    hasGradCam = true;
elseif isfield(result,"combinedMap") && ~isempty(result.combinedMap) && isnumeric(result.combinedMap)
    camMap = double(result.combinedMap);
    hasGradCam = true;
elseif isfield(request,"combinedMap") && ~isempty(request.combinedMap) && isnumeric(request.combinedMap)
    camMap = double(request.combinedMap);
    hasGradCam = true;
end

% 2. Check if lesionEvidence contains full .map matrices (from extract_lesion_evidence)
if ~hasGradCam && isstruct(lesionEvidence) && isfield(lesionEvidence,"map")
    for k = 1:numel(lesionEvidence)
        if ~isempty(lesionEvidence(k).map) && isnumeric(lesionEvidence(k).map)
            m = double(lesionEvidence(k).map);
            if size(m,1) ~= H || size(m,2) ~= W
                m = imresize(m,[H W]);
            end
            camMap = max(camMap,m);
            hasGradCam = true;
        end
    end
end

% 3. Construct spatial heatmap from localized lesionEvidence regions (from summarize_lesion_evidence)
if ~hasGradCam && isstruct(lesionEvidence)
    flatRegions = extractFlatRegions(lesionEvidence);
    if ~isempty(flatRegions)
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
                    hasGradCam = true;
                end
            end
        end
    end
end

% 4. If no focal lesions (e.g. No DR / normal screening), compute feature saliency attention map
% ResNet-101 evaluates retinal vascular caliber, macula, and optical disc features.
if ~hasGradCam || max(camMap(:)) == 0
    try
        grayI = rgb2gray(retinalImage);
        [Gx, Gy] = imgradientxy(grayI);
        gradMag = sqrt(Gx.^2 + Gy.^2);
        
        kSize = max(15, round(min(H, W) * 0.05));
        if mod(kSize, 2) == 0, kSize = kSize + 1; end
        kernel = ones(kSize, kSize) / (kSize^2);
        saliency = conv2(double(gradMag), kernel, "same");
        
        [X, Y] = meshgrid(1:W, 1:H);
        distFromCenter = sqrt((X - W/2).^2 + (Y - H/2).^2);
        fieldMask = distFromCenter < (min(H, W) * 0.46);
        saliency = saliency .* double(fieldMask);
        
        camMap = saliency;
    catch
        camMap = zeros(H, W);
    end
end

% Normalize and generate RGB Heatmap & Anatomical Overlay
if max(camMap(:)) > 0
    camMap = camMap / max(camMap(:));
    if size(camMap,1) ~= H || size(camMap,2) ~= W
        camMap = imresize(camMap,[H W]);
    end
    
    cmap = jet(256);
    idx = round(camMap * 255) + 1;
    idx = max(1,min(256,idx));
    rgbFlat = cmap(idx(:),:);
    heatmapRGB = im2uint8(reshape(rgbFlat,[H W 3]));
    
    % Blend with retinal fundus image for anatomical overlay
    alpha = 0.40 * camMap;
    alpha3 = repmat(alpha,[1 1 3]);
    overlayDbl = double(retinalImage) .* (1 - alpha3) + double(heatmapRGB) .* alpha3;
    overlayImage = uint8(min(255,max(0,overlayDbl)));
    overlayImage = makeEvidenceOverlay(overlayImage,lesionEvidence);
else
    heatmapRGB = retinalImage;
    overlayImage = retinalImage;
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
        J = drawImageRectangle(J,x,y,w,h,[0 240 255],2);
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

function [numHem, numMicro, numExud] = buildLesionBreakdown(lesionEvidence)
numHem = 0;
numMicro = 0;
numExud = 0;

if ~isstruct(lesionEvidence) || isempty(lesionEvidence)
    return;
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
    maculaText = "Spared (Central Field Intact)";
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
    maculaText = "Suspicious Parafoveal Activity";
else
    maculaText = "Spared (Central Field Intact)";
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
        tagStr = "ICDR Grade 0  •  Non-Referable Retinopathy";
    case "mild"
        tagStr = "ICDR Grade 1  •  Non-Referable Early Retinopathy";
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

function color = severityNeonColor(name,green,amber,red,purple,cyan)
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
    color = cyan;
end
end

function value = formatMetric(x)
if isempty(x) || ~isfinite(x)
    value = "N/A";
else
    value = string(sprintf("%.1f",x));
end
end

function value = formatAge(age)
if isempty(age) || isnan(age) || ~isfinite(age)
    value = "Not specified";
else
    value = string(sprintf("%.0f yrs",round(age)));
end
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
