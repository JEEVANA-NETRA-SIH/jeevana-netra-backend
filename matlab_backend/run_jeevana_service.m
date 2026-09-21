%% Jeevana Netra - Standalone service main (MATLAB Compiler CLI entry point)
%
% Executable usage (after mcc compilation):
%
%   run_jeevana_service <inputRequest.json> <outputResponse.json>
%
% The compiled standalone reads a request JSON file, dispatches on the
% "operation" field, runs the real Jeevana Netra pipeline, and writes a
% response JSON file (without leaking MATLAB stack traces to stdout).
%
% Supported operations:
%   screen          -> jeevana_netra_json_api
%   generate_report -> jeevana_report_json_api

function run_jeevana_service(varargin)

if numel(varargin) < 2
    writeErrorResponse("", ...
        "Usage: run_jeevana_service <inputRequest.json> <outputResponse.json>");
    return;
end

inputFile = char(varargin{1});
outputFile = char(varargin{2});

if ~isfile(inputFile)
    writeErrorResponse(outputFile, ...
        sprintf("Input request file not found: %s", inputFile));
    return;
end

try

    fid = fopen(inputFile,"r");
    raw = fread(fid,Inf,"*char")';
    fclose(fid);

    requestJson = strtrim(string(raw));

    if isempty(requestJson)
        error("jneeRun:EmptyRequest","Request JSON is empty.");
    end

    request = jsondecode(requestJson);

    if ~isfield(request,"operation")
        error("jneeRun:MissingOperation","Request operation is required.");
    end

    operation = lower(char(string(request.operation)));

    switch operation
        case "screen"
            outputJson = jeevana_netra_json_api(requestJson);
        case "generate_report"
            outputJson = jeevana_report_json_api(requestJson);
        otherwise
            error("jneeRun:UnsupportedOperation", ...
                "Unsupported operation: %s", operation);
    end

    outFid = fopen(outputFile,"w");
    if outFid == -1
        error("jneeRun:WriteFailed", ...
            "Unable to open output file: %s", outputFile);
    end
    fwrite(outFid,outputJson,"char");
    fclose(outFid);

catch ME
    writeErrorResponse(outputFile, ME.message);
end

end

%% Write a compact JSON error response instead of leaking a MATLAB stack.
function writeErrorResponse(outputFile, message)

payload = struct();
payload.status = "error";
payload.errorType = "MATLAB";
payload.message = string(message);

try
    jsonText = jsonencode(payload);
    if ~isempty(outputFile)
        fid = fopen(outputFile,"w");
        if fid ~= -1
            fwrite(fid,jsonText,"char");
            fclose(fid);
        end
    end
catch
end

fprintf("[jeevana_service] Error: %s\n", char(string(message)));

end