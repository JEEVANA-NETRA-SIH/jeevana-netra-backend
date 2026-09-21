function response = jeevana_report_api(requestJson)
% JEEVANA_REPORT_API
% Generates a two-page Jeevana Netra AI-assisted screening report.
%
% Input JSON fields:
%   operation, screeningId, patient, result, imageBytes
%
% imageBytes must contain encoded PNG or JPEG file bytes.
%
% Output fields:
%   status, filename, pdfBytes, sizeBytes

if nargin < 1 || isempty(requestJson)
    error("Request JSON is required.");
end

if isstring(requestJson)
    requestJson = char(requestJson);
end

if ~ischar(requestJson)
    error("Request must be a JSON string.");
end

request = jsondecode(requestJson);

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

if ~isfield(request,"imageBytes")
    error("Image bytes are required.");
end

patient = request.patient;
result = request.result;

patientName = getStringField(patient,"name","Unknown");
patientId = getStringField(patient,"id","Unknown");
patientGender = getStringField(patient,"gender","Not specified");
patientAge = getNumericField(patient,"age",NaN);

screeningId = "JN-REPORT";
if isfield(request,"screeningId") && ~isempty(request.screeningId)
    screeningId = string(request.screeningId);
end

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

imageBytes = uint8(request.imageBytes(:));
if isempty(imageBytes)
    error("Image bytes are empty.");
end

% ------------------------------------------------------------
% Decode PNG or JPEG bytes safely.
% ------------------------------------------------------------
if isPngBytes(imageBytes)
    imageExtension = ".png";
elseif isJpegBytes(imageBytes)
    imageExtension = ".jpg";
else
    error("Unsupported image format. imageBytes must contain PNG or JPEG file bytes.");
end

tempDir = tempdir;
tempImage = fullfile(tempDir,"jeevana_netra_report_input" + imageExtension);
tempPdf = fullfile(tempDir,"jeevana_netra_report.pdf");

deleteIfExists(tempImage);
deleteIfExists(tempPdf);

fid = fopen(tempImage,"wb");
if fid == -1
    error("Unable to create temporary image file.");
end
fwrite(fid,imageBytes,"uint8");
fclose(fid);

cleanupImage = onCleanup(@() deleteIfExists(tempImage)); %#ok<NASGU>

try
    retinalImage = imread(tempImage);
catch ME
    error("Unable to read retinal image: %s",ME.message);
end

if ndims(retinalImage) == 2
    retinalImage = repmat(retinalImage,[1 1 3]);
end

retinalImage = im2uint8(retinalImage);
enhancedImage = enhanceRetinalImage(retinalImage);
evidenceImage = makeEvidenceOverlay(retinalImage,lesionEvidence);

safePatientId = makeSafeFilename(patientId);
timeText = string(datetime("now","Format","yyyyMMdd_HHmmss"));
fileName = char("Jeevana_Netra_Report_" + safePatientId + "_" + timeText + ".pdf");

% ------------------------------------------------------------
% Palette.
% ------------------------------------------------------------
NAVY = [12 42 69] / 255;
NAVY2 = [20 55 82] / 255;
TEAL = [24 176 158] / 255;
GREEN = [47 145 60] / 255;
AMBER = [215 151 32] / 255;
RED = [190 57 47] / 255;
PURPLE = [108 77 160] / 255;
TEXT = [34 48 61] / 255;
MUTED = [91 108 123] / 255;
BG = [247 250 252] / 255;
CARD = [253 254 255] / 255;
GRID = [213 224 232] / 255;
WHITE = [1 1 1];

accent = severityColor(predictedClass,GREEN,AMBER,RED,PURPLE,NAVY2);
softAccent = blendWithWhite(accent,0.90);

% ============================================================
% PAGE 1 - SCREENING OVERVIEW
% ============================================================
fig = makePageFigure();
ax = makePageAxes(fig);

rectangle(ax,"Position",[0 0 100 140],"FaceColor",WHITE,"EdgeColor","none");
rectangle(ax,"Position",[0 0 100 22.5],"FaceColor",NAVY,"EdgeColor","none");
rectangle(ax,"Position",[0 21.8 100 0.7],"FaceColor",TEAL,"EdgeColor","none");

text(ax,5,5.8,"Jeevana Netra","Color",WHITE,"FontSize",21,"FontWeight","bold");
text(ax,5,10.2,"Seeing Today, Protecting Tomorrow","Color",[0.56 0.90 0.84],"FontSize",8.5);
text(ax,5,17.2,"AI-Assisted Diabetic Retinopathy Screening Report","Color",[0.82 0.88 0.93],"FontSize",10.5,"FontWeight","bold");
text(ax,94,5.8,"REPORT ID","Color",[0.63 0.73 0.82],"FontSize",6.5,"FontWeight","bold","HorizontalAlignment","right");
text(ax,94,9.8,string(screeningId),"Color",WHITE,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,94,15.2,"Generated " + string(datetime("now","Format","dd MMM yyyy HH:mm")),"Color",[0.76 0.84 0.90],"FontSize",7,"HorizontalAlignment","right","Interpreter","none");

% Result banner.
rectangle(ax,"Position",[4 27 92 15.5],"FaceColor",accent,"EdgeColor","none");
text(ax,6,30.6,string(predictedClass),"Color",WHITE,"FontSize",18,"FontWeight","bold","Interpreter","none");
text(ax,6,37.8,"AI SCREENING RESULT","Color",[0.91 0.96 0.98],"FontSize",7.2,"FontWeight","bold");
text(ax,49,31.0,"CONFIDENCE","Color",[0.91 0.96 0.98],"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center");
text(ax,49,36.0,sprintf("%.1f%%",confidence),"Color",WHITE,"FontSize",12.5,"FontWeight","bold","HorizontalAlignment","center");
text(ax,70,31.0,"REFERRAL","Color",[0.91 0.96 0.98],"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center");
text(ax,70,36.0,wrapText(char(referralStatus),14,2),"Color",WHITE,"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax,89.5,31.0,"EVIDENCE REGIONS","Color",[0.91 0.96 0.98],"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center");
text(ax,89.5,36.0,sprintf("%d",evidenceCount),"Color",WHITE,"FontSize",6.8,"FontWeight","bold","HorizontalAlignment","center");

% Patient card.
drawCard(ax,4,45.0,44,22.8,CARD,GRID);
text(ax,6,49.0,"PATIENT","Color",NAVY,"FontSize",9.5,"FontWeight","bold");
text(ax,6,53.6,"NAME","Color",MUTED,"FontSize",6.5,"FontWeight","bold");
text(ax,6,58.0,string(patientName),"Color",TEXT,"FontSize",10.0,"FontWeight","bold","Interpreter","none");
text(ax,27,53.6,"PATIENT ID","Color",MUTED,"FontSize",6.5,"FontWeight","bold");
text(ax,27,58.0,string(patientId),"Color",TEXT,"FontSize",8.5,"FontWeight","bold","Interpreter","none");
text(ax,6,62.5,"AGE","Color",MUTED,"FontSize",6.5,"FontWeight","bold");
text(ax,6,66.0,formatAge(patientAge),"Color",TEXT,"FontSize",8.5,"FontWeight","bold","Interpreter","none");
text(ax,27,62.5,"GENDER","Color",MUTED,"FontSize",6.5,"FontWeight","bold");
text(ax,27,66.0,string(patientGender),"Color",TEXT,"FontSize",8.5,"FontWeight","bold","Interpreter","none");

% Quality card.
drawCard(ax,52,45.0,44,22.8,CARD,GRID);
text(ax,54,49.0,"IMAGE QUALITY","Color",NAVY,"FontSize",9.5,"FontWeight","bold");
qualityAccent = qualityColor(qualityStatus,GREEN,AMBER,RED);
qualitySoft = blendWithWhite(qualityAccent,0.88);
rectangle(ax,"Position",[79.0 47.0 14.5 4.4],"FaceColor",qualitySoft,"EdgeColor",qualityAccent,"LineWidth",0.7);
text(ax,86.25,49.5,string(qualityStatus),"Color",qualityAccent,"FontSize",6.2,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");
text(ax,54,54.2,"BRIGHTNESS","Color",MUTED,"FontSize",6.3,"FontWeight","bold");
text(ax,54,58.5,formatMetric(brightness),"Color",TEXT,"FontSize",8.8,"FontWeight","bold");
text(ax,68.0,54.2,"CONTRAST","Color",MUTED,"FontSize",6.3,"FontWeight","bold");
text(ax,68.0,58.5,formatMetric(contrast),"Color",TEXT,"FontSize",8.8,"FontWeight","bold");
text(ax,82.0,54.2,"SHARPNESS","Color",MUTED,"FontSize",6.3,"FontWeight","bold");
text(ax,82.0,58.5,formatMetric(sharpness),"Color",TEXT,"FontSize",8.8,"FontWeight","bold");
text(ax,54,62.8,"QUALITY NOTE","Color",MUTED,"FontSize",6.1,"FontWeight","bold");
qualityMessageDisplay = "No quality issue message returned.";
if strlength(string(qualityMessage)) > 0
    qualityMessageDisplay = char(qualityMessage);
end
qualityMessageDisplay = wrapText(qualityMessageDisplay,42,1);
text(ax,54,65.6,qualityMessageDisplay,"Color",TEXT,"FontSize",5.8,"Interpreter","none","VerticalAlignment","top");

% Retinal image card.
drawCard(ax,4,71.0,58,46.5,CARD,GRID);
text(ax,6,75.3,"RETINAL IMAGE","Color",NAVY,"FontSize",9.5,"FontWeight","bold");
imageBox = [6 78.7 54 33.2];
rectangle(ax,"Position",imageBox,"FaceColor",[0.04 0.05 0.06],"EdgeColor",GRID,"LineWidth",0.7);
showImageInBox(ax,retinalImage,imageBox);
text(ax,33,114.5,"Original screening image","Color",MUTED,"FontSize",6.6,"HorizontalAlignment","center");

% Model confidence card.
drawCard(ax,64,71.0,32,46.5,CARD,GRID);
text(ax,66,75.3,"MODEL CONFIDENCE","Color",NAVY,"FontSize",9.2,"FontWeight","bold");
drawConfidenceRing(ax,80,91.0,9.0,confidence,accent,TEXT,MUTED);
text(ax,80,102.0,string(confidenceStatus),"Color",MUTED,"FontSize",6.4,"HorizontalAlignment","center","Interpreter","none");
text(ax,80,105.2,"Referral pathway","Color",MUTED,"FontSize",6.4,"HorizontalAlignment","center");
text(ax,80,108.6,wrapText(char(referralStatus),16,2),"Color",accent,"FontSize",7.5,"FontWeight","bold","HorizontalAlignment","center","Interpreter","none");

% Probabilities.
drawCard(ax,4,119.8,92,12.0,softAccent,GRID);
text(ax,6,122.9,"GRADE PROBABILITIES","Color",NAVY,"FontSize",8.5,"FontWeight","bold");
labels = {"No DR","Mild","Moderate","Severe","Proliferative"};
vals = [probabilities.NoDR probabilities.Mild probabilities.Moderate probabilities.Severe probabilities.ProliferativeDR];
startX = 23.0;
for i = 1:5
    x = startX + (i-1) * 14.2;
    text(ax,x,125.9,labels{i},"Color",MUTED,"FontSize",5.8,"FontWeight","bold","HorizontalAlignment","center");
    rectangle(ax,"Position",[x-5 127.0 10 2.5],"FaceColor",[0.91 0.94 0.96],"EdgeColor","none");
    fillW = max(0,min(10,vals(i) / 100 * 10));
    if fillW > 0
        rectangle(ax,"Position",[x-5 127.0 fillW 2.5],"FaceColor",probabilityColor(i),"EdgeColor","none");
    end
    text(ax,x,131.0,sprintf("%.1f%%",vals(i)),"Color",TEXT,"FontSize",6.3,"FontWeight","bold","HorizontalAlignment","center");
end

drawFooter(ax,MUTED,TEAL,1);

% Repaint the header after all other graphics are drawn.
% This preserves the existing header design while covering any stray
% diagonal/dotted line artifact that may be rendered over the header.
rectangle(ax,"Position",[0 0 100 22.5],"FaceColor",NAVY,"EdgeColor","none");
rectangle(ax,"Position",[0 21.8 100 0.7],"FaceColor",TEAL,"EdgeColor","none");
text(ax,5,5.8,"Jeevana Netra","Color",WHITE,"FontSize",21,"FontWeight","bold");
text(ax,5,10.2,"Seeing Today, Protecting Tomorrow","Color",[0.56 0.90 0.84],"FontSize",8.5);
text(ax,5,17.2,"AI-Assisted Diabetic Retinopathy Screening Report","Color",[0.82 0.88 0.93],"FontSize",10.5,"FontWeight","bold");
text(ax,94,5.8,"REPORT ID","Color",[0.63 0.73 0.82],"FontSize",6.5,"FontWeight","bold","HorizontalAlignment","right");
text(ax,94,9.8,string(screeningId),"Color",WHITE,"FontSize",8.5,"FontWeight","bold","HorizontalAlignment","right","Interpreter","none");
text(ax,94,15.2,"Generated " + string(datetime("now","Format","dd MMM yyyy HH:mm")),"Color",[0.76 0.84 0.90],"FontSize",7,"HorizontalAlignment","right","Interpreter","none");

exportgraphics(fig,tempPdf,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig);

% ============================================================
% PAGE 2 - EXPLAINABILITY AND ACTION
% ============================================================
fig = makePageFigure();
ax = makePageAxes(fig);

rectangle(ax,"Position",[0 0 100 140],"FaceColor",WHITE,"EdgeColor","none");
rectangle(ax,"Position",[0 0 100 20.0],"FaceColor",NAVY,"EdgeColor","none");
rectangle(ax,"Position",[0 19.2 100 0.8],"FaceColor",TEAL,"EdgeColor","none");
text(ax,5,5.8,"Jeevana Netra","Color",WHITE,"FontSize",20,"FontWeight","bold");
text(ax,5,11.0,"Explainability & Clinical Review Support","Color",[0.58 0.90 0.85],"FontSize",8.5);
text(ax,94,7.5,"Report ID: " + string(screeningId),"Color",[0.82 0.88 0.93],"FontSize",7.5,"HorizontalAlignment","right","Interpreter","none");

text(ax,5,25.0,"EXPLAINABILITY — WHAT THE SYSTEM CAN SHOW","Color",NAVY,"FontSize",11.5,"FontWeight","bold");
text(ax,5,29.0,"Visual evidence is derived from the submitted retinal image and returned lesion-evidence data.","Color",MUTED,"FontSize",7.0);

cardY = 33.0;
cardW = 29.0;
cardH = 36.0;
cardX = [4 35.5 67];
cardTitles = {"ORIGINAL IMAGE","ENHANCED VIEW","EVIDENCE OVERLAY"};
cardImages = {retinalImage,enhancedImage,evidenceImage};
cardCaptions = {"Submitted image","Preprocessed view","Supported evidence regions"};
for i = 1:3
    drawCard(ax,cardX(i),cardY,cardW,cardH,CARD,GRID);
    text(ax,cardX(i)+2,cardY+4.2,cardTitles{i},"Color",NAVY,"FontSize",7.5,"FontWeight","bold");
    box = [cardX(i)+2 cardY+8 cardW-4 24.5];
    rectangle(ax,"Position",box,"FaceColor",[0.04 0.05 0.06],"EdgeColor",GRID,"LineWidth",0.6);
    showImageInBox(ax,cardImages{i},box);
    text(ax,cardX(i)+cardW/2,cardY+34.0,cardCaptions{i},"Color",MUTED,"FontSize",6.1,"HorizontalAlignment","center","Interpreter","none");
end

% Evidence strip.
if evidenceCount > 0
    evidenceSummary = sprintf("%d evidence region(s) returned by the implemented evidence module.",evidenceCount);
    evidenceColor = accent;
else
    evidenceSummary = "No lesion evidence regions were returned for this screening.";
    evidenceColor = MUTED;
end
rectangle(ax,"Position",[4 71.5 92 8.5],"FaceColor",softAccent,"EdgeColor",accent,"LineWidth",0.8);
text(ax,6,75.0,"AI EVIDENCE","Color",accent,"FontSize",7.2,"FontWeight","bold");
text(ax,24,75.0,evidenceSummary,"Color",evidenceColor,"FontSize",7.1,"Interpreter","none");

% Detected region table.
drawSectionHeader(ax,82.8,"DETECTED REGIONS","Position","Area","Strength",TEXT,GRID,MUTED);
rows = makeEvidenceRows(lesionEvidence);
rowY = 91.8;
if isempty(rows)
    rectangle(ax,"Position",[5 91.6 90 8.0],"FaceColor",BG,"EdgeColor",GRID,"LineWidth",0.5);
    text(ax,7,94.8,"No detected region records were returned for this screening.","Color",MUTED,"FontSize",6.9,"Interpreter","none");
else
    maxRows = min(4,size(rows,1));
    for i = 1:maxRows
        rowColor = WHITE;
        if mod(i,2) == 0
            rowColor = BG;
        end
        rectangle(ax,"Position",[5 rowY 90 6.0],"FaceColor",rowColor,"EdgeColor",GRID,"LineWidth",0.4);
        text(ax,7,rowY+2.7,string(i),"Color",TEXT,"FontSize",6.8,"FontWeight","bold");
        text(ax,16,rowY+2.7,string(rows{i,1}),"Color",TEXT,"FontSize",6.7,"Interpreter","none");
        text(ax,55,rowY+2.7,string(rows{i,2}),"Color",TEXT,"FontSize",6.7,"Interpreter","none");
        text(ax,69,rowY+2.7,string(rows{i,3}),"Color",TEXT,"FontSize",6.7,"Interpreter","none");
        text(ax,82,rowY+2.7,string(rows{i,4}),"Color",TEXT,"FontSize",6.2,"Interpreter","none");
        rowY = rowY + 6.0;
    end
    if size(rows,1) > maxRows
        text(ax,7,rowY+2.7,sprintf("+%d additional evidence region(s) available in the returned data.",size(rows,1)-maxRows),"Color",MUTED,"FontSize",6.3,"Interpreter","none");
        rowY = rowY + 5.0;
    end
end

% Recommendation is positioned from the actual table height.
recY = min(118.5,rowY + 7.0);
text(ax,5,recY,"NEXT STEP / RECOMMENDATION","Color",NAVY,"FontSize",10.0,"FontWeight","bold");
recBoxY = recY + 2.1;
rectangle(ax,"Position",[5 recBoxY 90 8.6],"FaceColor",blendWithWhite(accent,0.93),"EdgeColor",GRID,"LineWidth",0.7);
rectangle(ax,"Position",[5 recBoxY 1.5 8.6],"FaceColor",accent,"EdgeColor","none");
recText = wrapText(char(recommendation),108,2);
text(ax,8,recBoxY+2.3,string(recText),"Color",TEXT,"FontSize",7.0,"Interpreter","none","VerticalAlignment","top");

disclaimerY = recBoxY + 10.8;
text(ax,5,disclaimerY,"Disclaimer: This report is an AI-assisted screening aid, not a clinical diagnosis. Findings should be reviewed by an appropriately qualified clinician.","Color",MUTED,"FontSize",5.8,"Interpreter","none");
drawFooter(ax,MUTED,TEAL,2);

% Repaint the header after all other graphics are drawn.
% This preserves the existing header design while covering any stray
% diagonal/dotted line artifact that may be rendered over the header.
rectangle(ax,"Position",[0 0 100 20.0],"FaceColor",NAVY,"EdgeColor","none");
rectangle(ax,"Position",[0 19.2 100 0.8],"FaceColor",TEAL,"EdgeColor","none");
text(ax,5,5.8,"Jeevana Netra","Color",WHITE,"FontSize",20,"FontWeight","bold");
text(ax,5,11.0,"Explainability & Clinical Review Support","Color",[0.58 0.90 0.85],"FontSize",8.5);
text(ax,94,7.5,"Report ID: " + string(screeningId),"Color",[0.82 0.88 0.93],"FontSize",7.5,"HorizontalAlignment","right","Interpreter","none");

exportgraphics(fig,tempPdf,"Append",true,"ContentType","image","Resolution",300,"BackgroundColor","white");
close(fig);

% ------------------------------------------------------------
% Return PDF bytes.
% ------------------------------------------------------------

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
% LOCAL FUNCTIONS
% ============================================================

function fig = makePageFigure()
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

function drawCard(ax,x,y,w,h,faceColor,borderColor)
rectangle(ax,"Position",[x y w h],"FaceColor",faceColor,"EdgeColor",borderColor,"LineWidth",0.8);
end

function showImageInBox(ax,I,box)
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

function drawConfidenceRing(ax,cx,cy,r,pct,accent,textColor,mutedColor)
t = linspace(0,2*pi,180);
plot(ax,cx+r*cos(t),cy+r*sin(t),"Color",[0.89 0.92 0.94],"LineWidth",4.5);
clampedPct = max(0,min(100,pct));
ang = linspace(pi/2,pi/2-2*pi*clampedPct/100,150);
plot(ax,cx+r*cos(ang),cy+r*sin(ang),"Color",accent,"LineWidth",4.5);
text(ax,cx,cy-1.2,sprintf("%.1f%%",pct),"Color",textColor,"FontSize",15,"FontWeight","bold","HorizontalAlignment","center");
text(ax,cx,cy+3.0,"confidence","Color",mutedColor,"FontSize",6.2,"HorizontalAlignment","center");
end

function drawSectionHeader(ax,y,title,a,b,c,textColor,gridColor,mutedColor)
text(ax,5,y,title,"Color",textColor,"FontSize",10,"FontWeight","bold");
rectangle(ax,"Position",[5 y+3 90 0.35],"FaceColor",gridColor,"EdgeColor","none");
text(ax,7,y+7,"#","Color",mutedColor,"FontSize",6.5,"FontWeight","bold");
text(ax,16,y+7,a,"Color",mutedColor,"FontSize",6.5,"FontWeight","bold");
text(ax,55,y+7,b,"Color",mutedColor,"FontSize",6.5,"FontWeight","bold");
text(ax,69,y+7,c,"Color",mutedColor,"FontSize",6.5,"FontWeight","bold");
text(ax,82,y+7,"Type / Zone","Color",mutedColor,"FontSize",6.5,"FontWeight","bold");
end

function drawFooter(ax,muted,teal,pageNo)
rectangle(ax,"Position",[5 135 90 0.35],"FaceColor",[0.83 0.88 0.91],"EdgeColor","none");
text(ax,5,138,"AI-Assisted Diabetic Retinopathy Screening","Color",muted,"FontSize",6.3);
text(ax,50,138,"Team Jeevana Netra  •  SIH 2026","Color",muted,"FontSize",6.3,"HorizontalAlignment","center");
text(ax,95,138,"Page " + string(pageNo),"Color",muted,"FontSize",6.3,"HorizontalAlignment","right");
text(ax,95,136.0,"AI FOR BETTER VISION","Color",teal,"FontSize",5.7,"FontWeight","bold","HorizontalAlignment","right");
end

function tf = isPngBytes(bytes)
tf = false;
if numel(bytes) < 8
    return;
end
signature = uint8([137 80 78 71 13 10 26 10]);
tf = isequal(bytes(1:8)',signature);
end

function tf = isJpegBytes(bytes)
tf = false;
if numel(bytes) < 3
    return;
end
signature = uint8([255 216 255]);
tf = isequal(bytes(1:3)',signature);
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

% Keep the complete string value. The previous implementation used
% raw(1), which returned only the first character for a char vector
% such as "Preethi K" or "JN-2026-003".
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

function color = severityColor(name,green,amber,red,purple,navy2)
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
    color = navy2;
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
    value = string(sprintf("%.0f",round(age)));
end
end

function c = probabilityColor(i)
colors = [GREEN_LOCAL(); AMBER_LOCAL(); [0.90 0.44 0.10]; RED_LOCAL(); [0.42 0.16 0.64]];
c = colors(i,:);
end

function c = GREEN_LOCAL()
c = [47 145 60] / 255;
end

function c = AMBER_LOCAL()
c = [215 151 32] / 255;
end

function c = RED_LOCAL()
c = [190 57 47] / 255;
end

function c = blendWithWhite(base,ratio)
c = base * (1-ratio) + [1 1 1] * ratio;
end

function J = enhanceRetinalImage(I)
I2 = im2double(I);
HSV = rgb2hsv(I2);
V = HSV(:,:,3);
V = adapthisteq(V,"NumTiles",[8 8],"ClipLimit",0.01);
V = imsharpen(V,"Radius",1,"Amount",0.5);
HSV(:,:,3) = min(1,max(0,V));
J = im2uint8(hsv2rgb(HSV));
end

function J = makeEvidenceOverlay(I,evidence)
J = I;
if ~isstruct(evidence) || isempty(evidence)
    return;
end

if isfield(evidence,"regions")
    for k = 1:numel(evidence)
        regs = evidence(k).regions;
        if ~isstruct(regs) || isempty(regs)
            continue;
        end
        for j = 1:numel(regs)
            [ok,x,y,w,h] = getRegionBox(regs(j),size(J));
            if ok
                J = drawImageRectangle(J,x,y,w,h,[255 220 0],2);
            end
        end
    end
else
    for j = 1:numel(evidence)
        [ok,x,y,w,h] = getRegionBox(evidence(j),size(J));
        if ok
            J = drawImageRectangle(J,x,y,w,h,[255 220 0],2);
        end
    end
end
end

function [ok,x,y,w,h] = getRegionBox(region,imageSize)
ok = false;
x = 0;
y = 0;
w = 0;
h = 0;
H = imageSize(1);
W = imageSize(2);

if isfield(region,"bbox") && isnumeric(region.bbox) && numel(region.bbox) >= 4
    b = double(region.bbox(:));
    x = b(1);
    y = b(2);
    w = b(3);
    h = b(4);
    ok = true;
elseif isfield(region,"x") && isfield(region,"y") && isfield(region,"w") && isfield(region,"h")
    x = double(region.x);
    y = double(region.y);
    w = double(region.w);
    h = double(region.h);
    ok = true;
elseif isfield(region,"x") && isfield(region,"y") && isfield(region,"width") && isfield(region,"height")
    x = double(region.x);
    y = double(region.y);
    w = double(region.width);
    h = double(region.height);
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
if isfield(evidence,"regions")
    for i = 1:numel(evidence)
        regs = evidence(i).regions;
        if isstruct(regs)
            n = n + numel(regs);
        elseif ~isempty(regs)
            n = n + 1;
        end
    end
else
    n = numel(evidence);
end
end

function rows = makeEvidenceRows(evidence)
rows = cell(0,4);
if ~isstruct(evidence) || isempty(evidence)
    return;
end

flat = cell(0,1);
if isfield(evidence,"regions")
    for i = 1:numel(evidence)
        regs = evidence(i).regions;
        if isstruct(regs)
            for j = 1:numel(regs)
                flat{end+1,1} = regs(j); %#ok<AGROW>
            end
        end
    end
else
    for i = 1:numel(evidence)
        flat{end+1,1} = evidence(i); %#ok<AGROW>
    end
end

for i = 1:numel(flat)
    r = flat{i};
    pos = "n/a";
    [ok,x,y,~,~] = getRegionBox(r,[512 512 3]);
    if ok
        pos = string(sprintf("(%d,%d)",round(x),round(y)));
    elseif isfield(r,"position")
        pos = string(r.position);
    end

    area = "n/a";
    if isfield(r,"area") && ~isempty(r.area)
        area = string(sprintf("%.0f px²",double(r.area)));
    end

    strength = "n/a";
    if isfield(r,"strength") && ~isempty(r.strength)
        strength = string(sprintf("%.1f",double(r.strength)));
    elseif isfield(r,"intensity") && ~isempty(r.intensity)
        strength = string(sprintf("%.1f",double(r.intensity)));
    end

    typeZone = getStringField(r,"type","evidence");
    if isfield(r,"zone") && ~isempty(r.zone)
        typeZone = typeZone + " / " + string(r.zone);
    elseif isfield(r,"note") && ~isempty(r.note)
        typeZone = typeZone + " / " + string(r.note);
    end

    rows(end+1,:) = {pos,area,strength,typeZone}; %#ok<AGROW>
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
