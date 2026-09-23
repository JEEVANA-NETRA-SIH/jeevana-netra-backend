function evidence = extract_lesion_evidence(I)
% JEEVANA NETRA
% Reusable lesion evidence extraction using:
% Patch-level ResNet-101 + Grad-CAM
%
% Input:
%   I = retinal RGB image
%
% Output:
%   evidence = structure containing lesion evidence for:
%              Microaneurysm
%              Haemorrhage
%              Hard Exudate
%              Soft Exudate

%% Locate packaged model files

modelFile = which('IDRiD_Lesion_Evidence_ResNet101.mat');
thresholdFile = which('IDRiD_Lesion_Evidence_Thresholds.mat');

if isempty(modelFile)
    modelFile = fullfile( ...
        fileparts(mfilename('fullpath')), ...
        'IDRiD_Lesion_Evidence_ResNet101.mat');
end

if isempty(thresholdFile)
    thresholdFile = fullfile( ...
        fileparts(mfilename('fullpath')), ...
        'IDRiD_Lesion_Evidence_Thresholds.mat');
end

if isempty(modelFile) || ~isfile(modelFile)
    error('IDRiD_Lesion_Evidence_ResNet101.mat could not be found.');
end

if isempty(thresholdFile) || ~isfile(thresholdFile)
    error('IDRiD_Lesion_Evidence_Thresholds.mat could not be found.');
end

%% Load model

persistent persistentNet persistentClassNames persistentInputSize persistentThresholds

if isempty(persistentNet)
    D = load(modelFile,'trainedNet','classNames','inputSize');
    persistentNet = D.trainedNet;
    persistentClassNames = string(D.classNames);
    persistentInputSize = double(D.inputSize);

    T = load(thresholdFile,'bestThresholds');
    persistentThresholds = double(T.bestThresholds);
end

net = persistentNet;
classNames = persistentClassNames;
inputSize = persistentInputSize;
thresholds = persistentThresholds;

patchSize = inputSize(1);
numClasses = numel(classNames);

%% Prepare image

if size(I,3) == 1
    I = repmat(I,[1 1 3]);
end

if ~isa(I,'uint8')
    I = im2uint8(I);
end

H = size(I,1);
W = size(I,2);

% Ensure image dimensions are at least patchSize
if H < patchSize || W < patchSize
    scale = max(patchSize / H, patchSize / W);
    I = imresize(I, ceil([H * scale, W * scale]));
    H = size(I,1);
    W = size(I,2);
end

%% Create patch locations

stride = 112;

xList = 1:stride:(W - patchSize + 1);
yList = 1:stride:(H - patchSize + 1);

numPatches = numel(xList) * numel(yList);

fprintf('\nTotal candidate patches: %d\n',numPatches);

%% Store patch information

patchScores = zeros(numPatches,numClasses);
patchX = zeros(numPatches,1);
patchY = zeros(numPatches,1);

patchCounter = 0;

%% Scan image

for yy = 1:numel(yList)

    y = yList(yy);

    for xx = 1:numel(xList)

        x = xList(xx);

        patchCounter = patchCounter + 1;

        patch = I(y:(y + patchSize - 1), ...
                  x:(x + patchSize - 1), :);

        X = im2single(patch);

        scoreVector = predict(net,X);

        scoreVector = double(squeeze(scoreVector));

        patchScores(patchCounter,:) = scoreVector(:)';
        patchX(patchCounter) = x;
        patchY(patchCounter) = y;

    end

end

%% Evidence output structure

evidence = struct();

evidence.classNames = classNames;
evidence.thresholds = thresholds;
evidence.imageSize = [H W];
evidence.patchSize = patchSize;
evidence.stride = stride;
evidence.lesion = repmat(struct( ...
    'type','', ...
    'threshold',0, ...
    'topPatches',struct([]), ...
    'usedPatches',0, ...
    'map',[], ...
    'hasEvidence',false),numClasses,1);
%% Process each lesion class

for c = 1:numClasses

    scores = patchScores(:,c);

    [sortedScores,order] = sort(scores,'descend');

    topN = min(8,numel(order));

    lesionMap = zeros(H,W);

    lesionWeight = zeros(H,W);

    usedCount = 0;

    topResults = struct([]);

    for j = 1:topN

        idx = order(j);

        score = sortedScores(j);

        x = patchX(idx);
        y = patchY(idx);

        topResults(j).score = score;
        topResults(j).x = x;
        topResults(j).y = y;

        if score < thresholds(c)
            continue;
        end

        patch = I(y:(y + patchSize - 1), ...
                  x:(x + patchSize - 1), :);

        X = im2single(patch);

        reductionFcn = @(z) z(c);

        cam = gradCAM( ...
            net, ...
            X, ...
            reductionFcn, ...
            'FeatureLayer','res5c_relu', ...
            'ReductionLayer','fc_lesion_evidence', ...
            'OutputUpsampling','bicubic', ...
            'ExecutionEnvironment','cpu');

        cam = double(squeeze(cam));

        if isempty(cam)
            continue;
        end

        cam(cam < 0) = 0;

        camMin = min(cam(:));
        camMax = max(cam(:));

        if camMax <= camMin
            continue;
        end

        cam = (cam - camMin) / (camMax - camMin);

        if size(cam,1) ~= patchSize || size(cam,2) ~= patchSize
            cam = imresize(cam,[patchSize patchSize]);
        end

        cam(cam < 0.50) = 0;

        lesionMap( ...
            y:(y + patchSize - 1), ...
            x:(x + patchSize - 1)) = ...
            lesionMap( ...
            y:(y + patchSize - 1), ...
            x:(x + patchSize - 1)) + cam * score;

        lesionWeight( ...
            y:(y + patchSize - 1), ...
            x:(x + patchSize - 1)) = ...
            lesionWeight( ...
            y:(y + patchSize - 1), ...
            x:(x + patchSize - 1)) + score;

        usedCount = usedCount + 1;

    end

    valid = lesionWeight > 0;

    lesionMap(valid) = lesionMap(valid) ./ lesionWeight(valid);

    mapMax = max(lesionMap(:));

    if mapMax > 0
        lesionMap = lesionMap / mapMax;
    end

    lesionName = char(classNames(c));

    lesionResult = struct();

    lesionResult.type = lesionName;
    lesionResult.threshold = thresholds(c);
    lesionResult.topPatches = topResults;
    lesionResult.usedPatches = usedCount;
    lesionResult.map = lesionMap;
    lesionResult.hasEvidence = any(lesionMap(:) > 0);

    evidence.lesion(c) = lesionResult;

    fprintf('\n%s\n',lesionName);
    if ~isempty(sortedScores)
        fprintf('Top score: %.4f\n',sortedScores(1));
    else
        fprintf('Top score: 0.0000\n');
    end
    fprintf('Threshold: %.4f\n',thresholds(c));
    fprintf('Grad-CAM patches used: %d\n',usedCount);

end

%% Combined evidence map

combinedMap = zeros(H,W);

for c = 1:numClasses

    currentMap = evidence.lesion(c).map;

    combinedMap = max(combinedMap,currentMap);

end

evidence.combinedMap = combinedMap;

fprintf('\nLesion evidence extraction completed.\n');

end