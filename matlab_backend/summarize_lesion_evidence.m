function summary = summarize_lesion_evidence(evidence)
% JEEVANA NETRA
% Converts large lesion evidence maps into compact API-friendly regions.

summary = repmat(struct( ...
    'type','', ...
    'threshold',0, ...
    'hasEvidence',false, ...
    'usedPatches',0, ...
    'topScore',0, ...
    'regions',struct([])), ...
    numel(evidence.lesion),1);
for c = 1:numel(evidence.lesion)

    lesion = evidence.lesion(c);

    S = struct();

    S.type = lesion.type;
    S.threshold = lesion.threshold;
    S.hasEvidence = lesion.hasEvidence;
    S.usedPatches = lesion.usedPatches;

    % Highest patch score
    if isempty(lesion.topPatches)
        S.topScore = 0;
    else
        scores = [lesion.topPatches.score];
        S.topScore = max(scores);
    end

    % Find evidence regions from Grad-CAM map
    cam = lesion.map;

    binaryMap = cam >= 0.50;

    CC = bwconncomp(binaryMap);

    regionData = struct([]);

    if CC.NumObjects > 0

        props = regionprops( ...
            CC, ...
            cam, ...
            'Area', ...
            'BoundingBox', ...
            'Centroid', ...
            'MeanIntensity', ...
            'MaxIntensity');

        valid = find([props.Area] >= 200);

        if ~isempty(valid)

            meanValues = zeros(numel(valid),1);

            for k = 1:numel(valid)
                meanValues(k) = props(valid(k)).MeanIntensity;
            end

            [~,order] = sort(meanValues,'descend');

            maxRegions = min(5,numel(order));

            regionData = repmat(struct( ...
                'type',char(lesion.type), ...
                'x',0, ...
                'y',0, ...
                'width',0, ...
                'height',0, ...
                'centerX',0, ...
                'centerY',0, ...
                'area',0, ...
                'strength',0),maxRegions,1);

            H = evidence.imageSize(1);
            W = evidence.imageSize(2);

            for r = 1:maxRegions

                p = props(valid(order(r)));

                box = p.BoundingBox;
                center = p.Centroid;

                regionData(r).type = char(lesion.type);
                regionData(r).x = box(1);
                regionData(r).y = box(2);
                regionData(r).width = box(3);
                regionData(r).height = box(4);

                regionData(r).centerX = center(1) / W;
                regionData(r).centerY = center(2) / H;

                regionData(r).area = p.Area;
                regionData(r).strength = p.MaxIntensity;

            end

        end

    end

    S.regions = regionData;

    summary(c) = S;

end

end