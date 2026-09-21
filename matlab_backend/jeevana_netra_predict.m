%% Jeevana Netra - Final Prediction Module

function result = jeevana_netra_predict(imagePath)

%% 1. Load trained model

persistent netFinal

if isempty(netFinal)

    % Portable model resolution.
    % 1) which() finds the model when the training/data files are on the
    %    MATLAB path or packaged inside the deployed archive (CTF).
    % 2) Fallback: resolve relative to this function's own file location,
    %    so development works from any checkout with no absolute path.
    modelFile = which("ResNet101_APTOS_Final_Trained.mat");

    if isempty(modelFile)
        modelFile = fullfile( ...
            fileparts(mfilename("fullpath")), ...
            "ResNet101_APTOS_Final_Trained.mat");
    end

    if isempty(modelFile) || ~isfile(modelFile)
        error("Trained model file could not be found.");
    end

    data = load(modelFile,"netFinal");

    netFinal = data.netFinal;

end

%% 2. Run image quality check

[~,quality] = ...
    preprocess_retinal_image(imagePath);

%% 3. Store image quality information

result.imagePath = imagePath;

result.qualityStatus = quality.status;
result.qualityMessage = quality.message;

result.brightness = quality.brightness;
result.contrast = quality.contrast;
result.sharpness = quality.sharpness;

%% 4. Stop if image quality is poor

if quality.status == "Poor"

    result.screeningStatus = "RETAKE REQUIRED";
    result.predictedClass = "Not available";
    result.confidence = 0;

    result.NoDRProbability = 0;
    result.MildProbability = 0;
    result.ModerateProbability = 0;
    result.SevereProbability = 0;
    result.ProliferativeDRProbability = 0;

    result.referralStatus = "NOT ASSESSED";

    result.confidenceStatus = "NOT ASSESSED";

    result.recommendation = quality.message;

    return;

end

%% 5. Prepare model input

% IMPORTANT:
% This uses exactly the same resizing approach used
% when the ResNet-101 model was trained.

modelInput = ...
    prepare_jeevana_model_input(imagePath);

%% 6. Predict

scores = predict(netFinal,modelInput);

scores = extractdata(scores);
scores = scores(:);

%% 7. Define DR classes

classNames = [
    "NoDR"
    "Mild"
    "Moderate"
    "Severe"
    "ProliferativeDR"
];

%% 8. Find predicted class

[maxProbability,classIndex] = max(scores);

predictedClass = classNames(classIndex);

%% 9. Store prediction

result.predictedClass = predictedClass;

result.confidence = maxProbability * 100;

%% 10. Store class probabilities

result.NoDRProbability = scores(1) * 100;

result.MildProbability = scores(2) * 100;

result.ModerateProbability = scores(3) * 100;

result.SevereProbability = scores(4) * 100;

result.ProliferativeDRProbability = scores(5) * 100;

%% 11. Determine referral status

if predictedClass == "Moderate" || ...
   predictedClass == "Severe" || ...
   predictedClass == "ProliferativeDR"

    result.referralStatus = "REFERABLE DR";

else

    result.referralStatus = "NON-REFERABLE DR";

end

%% 12. Determine confidence status

% Prototype thresholds based on the validation analysis.
% These are NOT clinical thresholds.

if result.confidence < 50

    result.confidenceStatus = "LOW";

    result.recommendation = ...
        "AI confidence is low. Doctor review recommended.";

elseif result.confidence < 75

    result.confidenceStatus = "MEDIUM";

    result.recommendation = ...
        "AI confidence is moderate. Doctor review recommended.";

else

    result.confidenceStatus = "HIGH";

    if result.referralStatus == "REFERABLE DR"

        result.recommendation = ...
            "Refer patient for further clinical evaluation.";

    else

        result.recommendation = ...
            "No referable DR detected by the AI screening model.";

    end

end

%% 13. Overall screening status

result.screeningStatus = "SCREENING COMPLETED";

%% 14. Display result

disp(" ");
disp("========================================");
disp("       JEEVANA NETRA AI RESULT");
disp("========================================");

fprintf("Quality Status : %s\n", ...
    result.qualityStatus);

fprintf("Predicted DR   : %s\n", ...
    result.predictedClass);

fprintf("Confidence     : %.2f%%\n", ...
    result.confidence);

fprintf("Confidence     : %s\n", ...
    result.confidenceStatus);

fprintf("Referral       : %s\n", ...
    result.referralStatus);

fprintf("Recommendation : %s\n", ...
    result.recommendation);

disp(" ");
disp("Class probabilities:");

fprintf("NoDR              : %.2f%%\n", ...
    result.NoDRProbability);

fprintf("Mild              : %.2f%%\n", ...
    result.MildProbability);

fprintf("Moderate          : %.2f%%\n", ...
    result.ModerateProbability);

fprintf("Severe            : %.2f%%\n", ...
    result.SevereProbability);

fprintf("ProliferativeDR   : %.2f%%\n", ...
    result.ProliferativeDRProbability);

disp("========================================");

end