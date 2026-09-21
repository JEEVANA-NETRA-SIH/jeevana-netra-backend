%% Jeevana Netra - JSON-contract screening API wrapper
%
% Input : requestJson - JSON string
%           {
%             "operation"      : "screen",
%             "imageBase64"    : "<base64-encoded PNG/JPEG file bytes>",
%             "includeEvidence": true | false   (optional, default true)
%           }
%
% Output: responseJson - JSON string
%           {
%             "status": "success",
%             "screening": { ...same fields as jeevana_netra_api... }
%           }
%
% This wrapper exists so the HTTP bridge only needs to exchange JSON
% strings with deployed MATLAB. The actual screening logic is unchanged:
% the wrapper simply decodes base64 to raw file bytes and hands them to
% the existing jeevana_netra_api function.

function responseJson = jeevana_netra_json_api(requestJson)

if isstring(requestJson)
    requestJson = char(requestJson);
end

if ~ischar(requestJson)
    error("jneeJsonApi:InvalidRequest","Request must be a JSON string.");
end

if isempty(strtrim(requestJson))
    error("jneeJsonApi:EmptyRequest","Request JSON is empty.");
end

request = jsondecode(requestJson);

if ~isfield(request,"operation")
    error("jneeJsonApi:MissingOperation","Request operation is required.");
end

if strcmpi(char(string(request.operation)),"screen") ~= 0
    error("jneeJsonApi:UnsupportedOperation", ...
        "Unsupported operation. Use screen.");
end

if ~isfield(request,"imageBase64")
    error("jneeJsonApi:MissingImage","imageBase64 is required.");
end

imageData = matlab.net.base64decode(char(request.imageBase64));

if isempty(imageData)
    error("jneeJsonApi:EmptyImage","imageBase64 is empty.");
end

includeEvidence = true;
if isfield(request,"includeEvidence") && ~isempty(request.includeEvidence)
    includeEvidence = logical(request.includeEvidence);
end

screening = jeevana_netra_api(imageData,includeEvidence);

response = struct();
response.status = "success";
response.screening = screening;

responseJson = jsonencode(response);

end