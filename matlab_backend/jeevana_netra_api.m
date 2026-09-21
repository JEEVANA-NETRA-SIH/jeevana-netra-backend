%% Jeevana Netra - Backend API Function

function response = jeevana_netra_api(imageData)

%% 1. Validate input

if nargin < 1 || isempty(imageData)
    error("Image data is required.");
end

if ~isa(imageData,"uint8")
    error("Image data must be uint8.");
end

%% 2. Create temporary image file

tempDir = tempdir;
tempImage = fullfile(tempDir,"jeevana_netra_input.png");

try

    fid = fopen(tempImage,"wb");

    if fid == -1
        error("Unable to create temporary image file.");
    end

    fwrite(fid,imageData,"uint8");
    fclose(fid);

    %% 3. Run Jeevana Netra DR prediction

    result = jeevana_netra_predict(tempImage);

    %% 4. Create basic API response

    response = struct();

    response.status = "success";

    response.screeningStatus = result.screeningStatus;

    response.qualityStatus = result.qualityStatus;

    response.qualityMessage = result.qualityMessage;

    response.predictedClass = result.predictedClass;

    response.confidence = result.confidence;

    response.confidenceStatus = result.confidenceStatus;

    response.referralStatus = result.referralStatus;

    response.recommendation = result.recommendation;

    %% 5. Class probabilities

    response.probabilities = struct();

    response.probabilities.NoDR = ...
        result.NoDRProbability;

    response.probabilities.Mild = ...
        result.MildProbability;

    response.probabilities.Moderate = ...
        result.ModerateProbability;

    response.probabilities.Severe = ...
        result.SevereProbability;

    response.probabilities.ProliferativeDR = ...
        result.ProliferativeDRProbability;

    %% 6. Image-quality measurements

    response.imageQuality = struct();

    response.imageQuality.brightness = ...
        result.brightness;

    response.imageQuality.contrast = ...
        result.contrast;

    response.imageQuality.sharpness = ...
        result.sharpness;

    %% 7. Default empty lesion evidence

    response.lesionEvidence = repmat(struct( ...
        'type','', ...
        'threshold',0, ...
        'hasEvidence',false, ...
        'usedPatches',0, ...
        'topScore',0, ...
        'regions',struct([])),0,1);

    %% 8. Run lesion evidence only for usable images

    if strcmpi(string(result.qualityStatus),"Good")

        fprintf('\nRunning lesion evidence extraction...\n');

        I = imread(tempImage);

        if size(I,3) == 1
            I = repmat(I,[1 1 3]);
        end

        evidence = extract_lesion_evidence(I);

        fprintf('\nCreating compact lesion evidence summary...\n');

        lesionSummary = summarize_lesion_evidence(evidence);

        response.lesionEvidence = lesionSummary;

    else

        fprintf('\nImage quality is not Good.\n');
        fprintf('Skipping lesion evidence extraction.\n');

    end

catch ME

    if exist(tempImage,"file")
        delete(tempImage);
    end

    rethrow(ME);

end

%% 9. Cleanup

if exist(tempImage,"file")
    delete(tempImage);
end

end