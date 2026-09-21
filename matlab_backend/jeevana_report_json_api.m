%% Jeevana Netra - JSON-contract report API wrapper
%
% Input : requestJson - JSON string matching the jeevana_report_api
%           contract:
%           {
%             "operation"  : "generate_report",
%             "screeningId": "JN-2026-001",
%             "patient"    : {"name","id","gender","age"},
%             "result"     : {...screening result fields...},
%             "imageBytes" : [ <PNG/JPEG file bytes as integers> ]
%           }
%
% Output: responseJson - JSON string
%           {
%             "status"   : "success",
%             "filename" : "Jeevana_Netra_Report_....pdf",
%             "sizeBytes": <n>,
%             "pdfBase64": "<base64-encoded PDF file bytes>"
%           }
%
% The PDF generation logic is entirely unchanged from jeevana_report_api.m.
% This wrapper only serializes the returned pdfBytes into base64 so the
% HTTP bridge can send the PDF over JSON.

function responseJson = jeevana_report_json_api(requestJson)

if isstring(requestJson)
    requestJson = char(requestJson);
end

if ~ischar(requestJson) || isempty(strtrim(requestJson))
    error("jneeReportJson:InvalidRequest","Request JSON is required.");
end

response = jeevana_report_api(char(requestJson));

out = struct();
out.status = "success";

if isfield(response,"filename")
    out.filename = char(response.filename);
else
    out.filename = "Jeevana_Netra_Report.pdf";
end

if isfield(response,"pdfBytes") && ~isempty(response.pdfBytes)
    pdfBytes = uint8(response.pdfBytes(:)');
    out.pdfBase64 = matlab.net.base64encode(pdfBytes);
    out.sizeBytes = double(numel(pdfBytes));
else
    error("jneeReportJson:MissingPdf","Report generator returned no PDF bytes.");
end

responseJson = jsonencode(out);

end