%% Jeevana Netra - Retinal Image Quality + Smart Retake

function [processedImage, quality] = preprocess_retinal_image(imagePath)

%% Read image
originalImage = imread(imagePath);

%% Ensure RGB
if size(originalImage,3) == 1
    originalImage = repmat(originalImage,[1 1 3]);
end

originalImage = im2uint8(originalImage);

%% Convert to grayscale
grayImage = rgb2gray(originalImage);

%% Measure brightness
brightness = mean(double(grayImage(:)));

%% Measure contrast
contrastValue = std(double(grayImage(:)));

%% Measure sharpness
[Gx,Gy] = imgradientxy(grayImage);
gradientMagnitude = sqrt(Gx.^2 + Gy.^2);
sharpness = var(double(gradientMagnitude(:)));

%% Initial quality flags
isTooDark = brightness < 30;
isTooBright = brightness > 220;
isLowContrast = contrastValue < 20;
isVeryBlurry = sharpness < 60;

%% Determine quality and retake message

problems = strings(0);

if isTooDark
    problems(end+1) = "too dark";
end

if isTooBright
    problems(end+1) = "too bright";
end

if isLowContrast
    problems(end+1) = "low contrast";
end

if isVeryBlurry
    problems(end+1) = "blurry";
end

%% Create final quality result

if isempty(problems)

    quality.status = "Good";

    quality.message = ...
        "Image quality is suitable for analysis.";

else

    quality.status = "Poor";

    if numel(problems) == 1

        switch problems(1)

            case "too dark"
                quality.message = ...
                    "Image is too dark. Improve lighting and capture again.";

            case "too bright"
                quality.message = ...
                    "Image is too bright. Reduce exposure and capture again.";

            case "low contrast"
                quality.message = ...
                    "Image has low contrast. Capture a clearer retinal image.";

            case "blurry"
                quality.message = ...
                    "Image appears blurry. Keep the camera steady and refocus.";

        end

    else

        quality.message = ...
            "Retake required: " + strjoin(problems,", ") + ...
            ". Please capture a clearer retinal image.";

    end

end

%% Moderate contrast enhancement

labImage = rgb2lab(originalImage);

L = labImage(:,:,1);

% Mild CLAHE enhancement
L = adapthisteq(L/100, ...
    'NumTiles',[8 8], ...
    'ClipLimit',0.01);

labImage(:,:,1) = L*100;

enhancedImage = lab2rgb(labImage);

enhancedImage = im2uint8(enhancedImage);


%% Resize while preserving the complete retinal field

targetSize = [224 224];

[h,w,~] = size(enhancedImage);

% Calculate scale so the COMPLETE image fits inside 224x224
scale = min(targetSize(1)/h, targetSize(2)/w);

newH = round(h * scale);
newW = round(w * scale);

% Resize without changing aspect ratio
resizedImage = imresize(enhancedImage,[newH newW]);

% Use the average border intensity as padding
grayResized = rgb2gray(resizedImage);
padValue = uint8(mean(grayResized(:)));

processedImage = repmat( ...
    padValue, ...
    targetSize(1), ...
    targetSize(2), ...
    3);

% Center the COMPLETE resized image
rowStart = floor((targetSize(1)-newH)/2) + 1;
colStart = floor((targetSize(2)-newW)/2) + 1;

processedImage( ...
    rowStart:rowStart+newH-1, ...
    colStart:colStart+newW-1, :) = resizedImage;
%% Store measurements

quality.brightness = brightness;
quality.contrast = contrastValue;
quality.sharpness = sharpness;

%% Display result

fprintf("\n=====================================\n");
fprintf("JEEVANA NETRA IMAGE QUALITY\n");
fprintf("=====================================\n");

fprintf("Brightness : %.2f\n",brightness);
fprintf("Contrast   : %.2f\n",contrastValue);
fprintf("Sharpness  : %.2f\n",sharpness);
fprintf("Status     : %s\n",quality.status);
fprintf("Message    : %s\n",quality.message);

end