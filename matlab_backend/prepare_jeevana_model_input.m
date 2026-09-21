%% Jeevana Netra - Model-Compatible Input Preparation

function modelInput = prepare_jeevana_model_input(imagePath)

%% 1. Read original image

image = imread(imagePath);

%% 2. Ensure RGB

if size(image,3) == 1
    image = repmat(image,[1 1 3]);
end

%% 3. Convert to uint8

image = im2uint8(image);

%% 4. Resize exactly like the training pipeline

% The ResNet-101 model was trained using 224x224 resized images.
modelInput = imresize(image,[224 224]);

%% 5. Convert to single precision

modelInput = single(modelInput);

end