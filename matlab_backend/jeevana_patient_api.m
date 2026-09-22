%% JEEVANA NETRA - PATIENT / SCREENING DATABASE API (REFERENCE IMPLEMENTATION)
%
% Note: Active production persistence is handled by the FastAPI HTTP bridge
% (SQLAlchemy) as Database Toolbox cannot be packaged with MATLAB Compiler.
% This file is preserved for reference and standalone MATLAB testing.
%
% Real SQLite-backed patient and screening data service.
%
% Supported operations:
%
%   initialize
%   save_screening
%   get_screening_history
%   get_patient_records
%   get_patient_history
%
% Database path:
%
%   JEEVANA_NETRA_DB
%
% If not set:
%
%   <current folder>/JeevanaNetraData/jeevana_netra.db

function response = jeevana_patient_api(request)

%% =========================================================
% 1. VALIDATE AND DECODE REQUEST
% ==========================================================

if nargin < 1 || isempty(request)
    error("Request is required.");
end

if ischar(request) || ...
        (isstring(request) && isscalar(request))

    try
        request = jsondecode(char(request));
    catch ME
        error( ...
            "Invalid JSON request: %s", ...
            ME.message);
    end

elseif ~isstruct(request)

    error( ...
        "Request must be a JSON string or a scalar MATLAB struct.");

end

if numel(request) ~= 1
    error("Request must contain exactly one request object.");
end

if ~isfield(request,"operation") || ...
        isempty(request.operation)

    error("Request operation is required.");

end

operation = lower(string(request.operation));


%% =========================================================
% 2. OPEN DATABASE
% ==========================================================

dbPath = getDatabasePath();

conn = openDatabase(dbPath);


%% =========================================================
% 3. RUN OPERATION
% ==========================================================

try

    initializeDatabase(conn);

    switch operation

        case "initialize"

            response = struct();

            response.status = "success";
            response.operation = "initialize";
            response.database = dbPath;
            response.message = ...
                "Jeevana Netra SQLite database is ready.";


        case "save_screening"

            response = saveScreening( ...
                conn, ...
                request);


        case "get_screening_history"

            response = getScreeningHistory(conn);


        case "get_patient_records"

            response = getPatientRecords(conn);


        case "get_patient_history"

            response = getPatientHistory( ...
                conn, ...
                request);


        otherwise

            error( ...
                "Unsupported operation: %s", ...
                operation);

    end

    close(conn);

catch ME

    if isopen(conn)
        close(conn);
    end

    rethrow(ME);

end

end


%% =========================================================
% DATABASE PATH
% ==========================================================

function dbPath = getDatabasePath()

dbPath = getenv("JEEVANA_NETRA_DB");

if isempty(dbPath)

    baseDir = fullfile( ...
        pwd, ...
        "JeevanaNetraData");

    dbPath = fullfile( ...
        baseDir, ...
        "jeevana_netra.db");

end

dbPath = char(dbPath);

parentDir = fileparts(dbPath);

if ~isempty(parentDir) && ...
        ~isfolder(parentDir)

    mkdir(parentDir);

end

end


%% =========================================================
% OPEN SQLITE DATABASE
% ==========================================================

function conn = openDatabase(dbPath)

if isfile(dbPath)

    conn = sqlite( ...
        dbPath, ...
        "connect");

else

    conn = sqlite( ...
        dbPath, ...
        "create");

end

execute( ...
    conn, ...
    "PRAGMA foreign_keys = ON");

end


%% =========================================================
% INITIALIZE DATABASE TABLES
% ==========================================================

function initializeDatabase(conn)

%% PATIENTS TABLE

patientTableSQL = ...
    "CREATE TABLE IF NOT EXISTS patients (" + ...
    "patient_id TEXT PRIMARY KEY NOT NULL, " + ...
    "name TEXT NOT NULL, " + ...
    "age INTEGER, " + ...
    "gender TEXT, " + ...
    "created_at TEXT NOT NULL, " + ...
    "updated_at TEXT NOT NULL" + ...
    ")";

execute(conn,patientTableSQL);


%% SCREENINGS TABLE

screeningTableSQL = ...
    "CREATE TABLE IF NOT EXISTS screenings (" + ...
    "screening_pk INTEGER PRIMARY KEY AUTOINCREMENT, " + ...
    "screening_id TEXT UNIQUE NOT NULL, " + ...
    "patient_id TEXT NOT NULL, " + ...
    "screening_date TEXT NOT NULL, " + ...
    "predicted_class TEXT NOT NULL, " + ...
    "confidence REAL, " + ...
    "confidence_status TEXT, " + ...
    "referral_status TEXT, " + ...
    "recommendation TEXT, " + ...
    "quality_status TEXT, " + ...
    "quality_message TEXT, " + ...
    "brightness REAL, " + ...
    "contrast REAL, " + ...
    "sharpness REAL, " + ...
    "probabilities_json TEXT, " + ...
    "lesion_evidence_json TEXT, " + ...
    "FOREIGN KEY(patient_id) REFERENCES patients(patient_id)" + ...
    ")";

execute(conn,screeningTableSQL);


%% INDEXES

patientIndexSQL = ...
    "CREATE INDEX IF NOT EXISTS idx_screenings_patient " + ...
    "ON screenings(patient_id)";

execute(conn,patientIndexSQL);


dateIndexSQL = ...
    "CREATE INDEX IF NOT EXISTS idx_screenings_date " + ...
    "ON screenings(screening_date)";

execute(conn,dateIndexSQL);

end


%% =========================================================
% SAVE SCREENING
% ==========================================================

function response = saveScreening(conn,request)

%% PATIENT INFORMATION

patientId = getRequiredText( ...
    request, ...
    "patientId");

patientName = getRequiredText( ...
    request, ...
    "name");

age = getNumericField( ...
    request, ...
    "age", ...
    NaN);

gender = getTextField( ...
    request, ...
    "gender", ...
    "");


%% SCREENING INFORMATION

predictedClass = getRequiredText( ...
    request, ...
    "predictedClass");

confidence = getNumericField( ...
    request, ...
    "confidence", ...
    0);

confidenceStatus = getTextField( ...
    request, ...
    "confidenceStatus", ...
    "");

referralStatus = getTextField( ...
    request, ...
    "referralStatus", ...
    "");

recommendation = getTextField( ...
    request, ...
    "recommendation", ...
    "");

qualityStatus = getTextField( ...
    request, ...
    "qualityStatus", ...
    "");

qualityMessage = getTextField( ...
    request, ...
    "qualityMessage", ...
    "");

brightness = getNumericField( ...
    request, ...
    "brightness", ...
    0);

contrast = getNumericField( ...
    request, ...
    "contrast", ...
    0);

sharpness = getNumericField( ...
    request, ...
    "sharpness", ...
    0);


%% OPTIONAL STRUCTURED DATA

if isfield(request,"probabilities")

    probabilitiesJSON = jsonencode( ...
        request.probabilities);

else

    probabilitiesJSON = "{}";

end


if isfield(request,"lesionEvidence")

    lesionEvidenceJSON = jsonencode( ...
        request.lesionEvidence);

else

    lesionEvidenceJSON = "[]";

end


%% VALIDATE AGE

if ~isnan(age)

    age = floor(age);

    if age < 0 || age > 130

        error( ...
            "Patient age must be between 0 and 130.");

    end

end


%% CURRENT TIMESTAMP

nowText = char( ...
    datetime( ...
        "now", ...
        "Format", ...
        "yyyy-MM-dd HH:mm:ss"));


%% CREATE OR UPDATE PATIENT

existingPatient = fetch( ...
    conn, ...
    "SELECT patient_id FROM patients WHERE patient_id = " + ...
    sqlQuote(patientId));


if height(existingPatient) == 0

    patientInsertSQL = ...
        "INSERT INTO patients (" + ...
        "patient_id, name, age, gender, created_at, updated_at" + ...
        ") VALUES (" + ...
        sqlQuote(patientId) + ", " + ...
        sqlQuote(patientName) + ", " + ...
        sqlNumber(age) + ", " + ...
        sqlQuote(gender) + ", " + ...
        sqlQuote(nowText) + ", " + ...
        sqlQuote(nowText) + ...
        ")";

    execute(conn,patientInsertSQL);

else

    patientUpdateSQL = ...
        "UPDATE patients SET " + ...
        "name = " + sqlQuote(patientName) + ", " + ...
        "age = " + sqlNumber(age) + ", " + ...
        "gender = " + sqlQuote(gender) + ", " + ...
        "updated_at = " + sqlQuote(nowText) + ...
        " WHERE patient_id = " + ...
        sqlQuote(patientId);

    execute(conn,patientUpdateSQL);

end


%% SCREENING DATE

screeningDate = getTextField( ...
    request, ...
    "screeningDate", ...
    nowText);

if isempty(strtrim(screeningDate))

    screeningDate = nowText;

end


%% APPLICATION STATUS

screeningStatus = determineScreeningStatus( ...
    predictedClass, ...
    qualityStatus, ...
    referralStatus);


%% APPLICATION RISK

risk = determineRiskLevel( ...
    predictedClass);


%% GENERATE SCREENING ID

screeningId = generateScreeningId( ...
    conn, ...
    screeningDate);


%% INSERT SCREENING

screeningInsertSQL = ...
    "INSERT INTO screenings (" + ...
    "screening_id, " + ...
    "patient_id, " + ...
    "screening_date, " + ...
    "predicted_class, " + ...
    "confidence, " + ...
    "confidence_status, " + ...
    "referral_status, " + ...
    "recommendation, " + ...
    "quality_status, " + ...
    "quality_message, " + ...
    "brightness, " + ...
    "contrast, " + ...
    "sharpness, " + ...
    "probabilities_json, " + ...
    "lesion_evidence_json" + ...
    ") VALUES (" + ...
    sqlQuote(screeningId) + ", " + ...
    sqlQuote(patientId) + ", " + ...
    sqlQuote(screeningDate) + ", " + ...
    sqlQuote(predictedClass) + ", " + ...
    sqlNumber(confidence) + ", " + ...
    sqlQuote(confidenceStatus) + ", " + ...
    sqlQuote(referralStatus) + ", " + ...
    sqlQuote(recommendation) + ", " + ...
    sqlQuote(qualityStatus) + ", " + ...
    sqlQuote(qualityMessage) + ", " + ...
    sqlNumber(brightness) + ", " + ...
    sqlNumber(contrast) + ", " + ...
    sqlNumber(sharpness) + ", " + ...
    sqlQuote(probabilitiesJSON) + ", " + ...
    sqlQuote(lesionEvidenceJSON) + ...
    ")";

execute(conn,screeningInsertSQL);


%% RESPONSE

response = struct();

response.status = "success";

response.operation = "save_screening";

response.patientId = patientId;

response.screeningId = screeningId;

response.screeningStatus = screeningStatus;

response.risk = risk;

response.screeningDate = screeningDate;

response.message = ...
    "Patient and screening record saved successfully.";

end


%% =========================================================
% GET ALL SCREENING HISTORY
% ==========================================================

function response = getScreeningHistory(conn)

query = ...
    "SELECT " + ...
    "s.screening_id AS id, " + ...
    "p.name AS patient, " + ...
    "s.predicted_class AS result, " + ...
    "CASE " + ...
        "WHEN s.predicted_class IN " + ...
            "('Moderate','Severe','ProliferativeDR') THEN 'High' " + ...
        "WHEN s.predicted_class = 'Mild' THEN 'Medium' " + ...
        "ELSE 'Low' " + ...
    "END AS risk, " + ...
    "s.screening_date AS screening_date, " + ...
    "CASE " + ...
        "WHEN s.quality_status <> 'Good' THEN 'Pending' " + ...
        "WHEN s.referral_status = 'REFERABLE DR' THEN 'Requires Review' " + ...
        "ELSE 'Completed' " + ...
    "END AS status " + ...
    "FROM screenings s " + ...
    "INNER JOIN patients p " + ...
        "ON p.patient_id = s.patient_id " + ...
    "ORDER BY s.screening_date DESC, " + ...
    "s.screening_id DESC";

rows = fetch(conn,query);

count = height(rows);


history = repmat( ...
    struct( ...
        "id","", ...
        "patient","", ...
        "result","", ...
        "risk","", ...
        "date","", ...
        "status",""), ...
    count, ...
    1);


for i = 1:count

    history(i).id = ...
        char(string(rows.id(i)));

    history(i).patient = ...
        char(string(rows.patient(i)));

    history(i).result = ...
        char(string(rows.result(i)));

    history(i).risk = ...
        char(string(rows.risk(i)));

    history(i).date = ...
        formatDateLabel(rows.screening_date(i));

    history(i).status = ...
        char(string(rows.status(i)));

end


response = struct();

response.status = "success";

response.operation = ...
    "get_screening_history";

response.count = count;

response.screeningHistory = history;

end


%% =========================================================
% GET PATIENT RECORDS
% ==========================================================

function response = getPatientRecords(conn)

query = ...
    "SELECT " + ...
    "p.patient_id AS id, " + ...
    "p.name AS name, " + ...
    "p.age AS age, " + ...
    "p.gender AS gender, " + ...
    "s.screening_date AS screening_date, " + ...
    "s.predicted_class AS result, " + ...
    "CASE " + ...
        "WHEN s.predicted_class IN " + ...
            "('Moderate','Severe','ProliferativeDR') THEN 'High' " + ...
        "WHEN s.predicted_class = 'Mild' THEN 'Medium' " + ...
        "ELSE 'Low' " + ...
    "END AS risk, " + ...
    "CASE " + ...
        "WHEN s.quality_status <> 'Good' THEN 'Pending' " + ...
        "WHEN s.referral_status = 'REFERABLE DR' THEN 'Requires Review' " + ...
        "ELSE 'Completed' " + ...
    "END AS status " + ...
    "FROM patients p " + ...
    "LEFT JOIN screenings s " + ...
        "ON s.screening_pk = (" + ...
            "SELECT s2.screening_pk " + ...
            "FROM screenings s2 " + ...
            "WHERE s2.patient_id = p.patient_id " + ...
            "ORDER BY s2.screening_date DESC, " + ...
            "s2.screening_pk DESC " + ...
            "LIMIT 1" + ...
        ")" + ...
    "ORDER BY s.screening_date DESC, p.name ASC";

rows = fetch(conn,query);

count = height(rows);


patients = repmat( ...
    struct( ...
        "id","", ...
        "name","", ...
        "age",NaN, ...
        "gender","", ...
        "lastScreening","", ...
        "result","", ...
        "risk","", ...
        "status",""), ...
    count, ...
    1);


for i = 1:count

    patients(i).id = ...
        char(string(rows.id(i)));

    patients(i).name = ...
        char(string(rows.name(i)));


    if isnan(rows.age(i))

        patients(i).age = NaN;

    else

        patients(i).age = rows.age(i);

    end


    if ismissing(rows.gender(i))

        patients(i).gender = "";

    else

        patients(i).gender = ...
            char(string(rows.gender(i)));

    end


    if ismissing(rows.screening_date(i))

        patients(i).lastScreening = "";
        patients(i).result = "";
        patients(i).risk = "";
        patients(i).status = "";

    else

        patients(i).lastScreening = ...
            formatDateLabel(rows.screening_date(i));

        patients(i).result = ...
            char(string(rows.result(i)));

        patients(i).risk = ...
            char(string(rows.risk(i)));

        patients(i).status = ...
            char(string(rows.status(i)));

    end

end


response = struct();

response.status = "success";

response.operation = ...
    "get_patient_records";

response.count = count;

response.patientRecords = patients;

end


%% =========================================================
% GET INDIVIDUAL PATIENT HISTORY
% ==========================================================

function response = getPatientHistory(conn,request)

patientId = getRequiredText( ...
    request, ...
    "patientId");


query = ...
    "SELECT " + ...
    "s.screening_id, " + ...
    "s.screening_date, " + ...
    "s.predicted_class, " + ...
    "s.confidence, " + ...
    "s.confidence_status, " + ...
    "s.referral_status, " + ...
    "s.recommendation, " + ...
    "s.quality_status, " + ...
    "s.quality_message, " + ...
    "s.brightness, " + ...
    "s.contrast, " + ...
    "s.sharpness, " + ...
    "s.probabilities_json, " + ...
    "s.lesion_evidence_json " + ...
    "FROM screenings s " + ...
    "WHERE s.patient_id = " + ...
    sqlQuote(patientId) + ...
    " ORDER BY s.screening_date ASC, " + ...
    "s.screening_pk ASC";

rows = fetch(conn,query);

count = height(rows);


history = repmat( ...
    struct( ...
        "screeningId","", ...
        "date","", ...
        "result","", ...
        "risk","", ...
        "confidence",0, ...
        "confidenceStatus","", ...
        "referralStatus","", ...
        "recommendation","", ...
        "qualityStatus","", ...
        "qualityMessage","", ...
        "brightness",0, ...
        "contrast",0, ...
        "sharpness",0, ...
        "probabilities",struct(), ...
        "lesionEvidence",[]), ...
    count, ...
    1);


for i = 1:count

    history(i).screeningId = ...
        char(string(rows.screening_id(i)));

    history(i).date = ...
        formatDateLabel(rows.screening_date(i));

    history(i).result = ...
        char(string(rows.predicted_class(i)));

    history(i).risk = ...
        determineRiskLevel( ...
            char(string(rows.predicted_class(i))));

    history(i).confidence = ...
        rows.confidence(i);

    history(i).confidenceStatus = ...
        char(string(rows.confidence_status(i)));

    history(i).referralStatus = ...
        char(string(rows.referral_status(i)));

    history(i).recommendation = ...
        char(string(rows.recommendation(i)));

    history(i).qualityStatus = ...
        char(string(rows.quality_status(i)));

    history(i).qualityMessage = ...
        char(string(rows.quality_message(i)));

    history(i).brightness = ...
        rows.brightness(i);

    history(i).contrast = ...
        rows.contrast(i);

    history(i).sharpness = ...
        rows.sharpness(i);


    %% PROBABILITIES

    try

        probabilityText = ...
            char(string(rows.probabilities_json(i)));

        if ~isempty(strtrim(probabilityText))

            history(i).probabilities = ...
                jsondecode(probabilityText);

        else

            history(i).probabilities = struct();

        end

    catch

        history(i).probabilities = struct();

    end


    %% LESION EVIDENCE

    try

        lesionText = ...
            char(string(rows.lesion_evidence_json(i)));

        if ~isempty(strtrim(lesionText))

            history(i).lesionEvidence = ...
                jsondecode(lesionText);

        else

            history(i).lesionEvidence = [];

        end

    catch

        history(i).lesionEvidence = [];

    end

end


response = struct();

response.status = "success";

response.operation = ...
    "get_patient_history";

response.patientId = patientId;

response.count = count;

response.history = history;

end


%% =========================================================
% DETERMINE SCREENING STATUS
% ==========================================================

function status = determineScreeningStatus( ...
    predictedClass, ...
    qualityStatus, ...
    referralStatus)

if ~strcmpi( ...
        string(qualityStatus), ...
        "Good")

    status = "Pending";

    return;

end


if strcmpi( ...
        string(referralStatus), ...
        "REFERABLE DR")

    status = "Requires Review";

    return;

end


status = "Completed";

end


%% =========================================================
% DETERMINE RISK LEVEL
% ==========================================================

function risk = determineRiskLevel(predictedClass)

switch string(predictedClass)

    case "Mild"

        risk = "Medium";

    case {"Moderate","Severe","ProliferativeDR"}

        risk = "High";

    case {"Not available","RETAKE REQUIRED",""}

        risk = "Unassessed";

    otherwise

        risk = "Low";

end

end


%% =========================================================
% GENERATE SCREENING ID
% ==========================================================

function screeningId = generateScreeningId( ...
    conn, ...
    screeningDate)

rawDate = char(string(screeningDate));

%% Get year from screening date

yearText = "";

if numel(rawDate) >= 4

    candidateYear = rawDate(1:4);

    if all(isstrprop(candidateYear,"digit"))

        yearText = candidateYear;

    end

end


%% Fallback to current year

if isempty(yearText)

    yearText = char( ...
        string(year(datetime("now"))));

end


%% Find current highest screening number.
% COALESCE converts NULL to 0 when no screening exists.

query = ...
    "SELECT COALESCE(" + ...
    "MAX(CAST(substr(screening_id,9) AS INTEGER)),0) " + ...
    "AS max_num " + ...
    "FROM screenings " + ...
    "WHERE substr(screening_id,4,4) = " + ...
    sqlQuote(yearText);


rows = fetch(conn,query);


%% Generate next number

nextNumber = 1;

if height(rows) > 0

    maxNum = rows.max_num(1);

    if ~ismissing(maxNum) && ...
            ~isnan(maxNum)

        nextNumber = ...
            double(maxNum) + 1;

    end

end


%% Final screening ID

screeningId = sprintf( ...
    "JN-%s-%03d", ...
    yearText, ...
    nextNumber);

end


%% =========================================================
% FORMAT DATE FOR FRONTEND
% ==========================================================

function label = formatDateLabel(value)

if ismissing(value) || isempty(value)

    label = "";

    return;

end


raw = char(string(value));


try

    dt = datetime( ...
        raw, ...
        "InputFormat", ...
        "yyyy-MM-dd HH:mm:ss");

    label = char( ...
        string( ...
            datestr(dt,"dd mmm yyyy")));

catch

    label = raw;

end

end


%% =========================================================
% REQUIRED TEXT FIELD
% ==========================================================

function value = getRequiredText( ...
    request, ...
    fieldName)

if ~isfield(request,fieldName)

    error( ...
        "Required field '%s' is missing.", ...
        fieldName);

end


value = getTextField( ...
    request, ...
    fieldName, ...
    "");


if isempty(strtrim(value))

    error( ...
        "Required field '%s' is empty.", ...
        fieldName);

end

end


%% =========================================================
% TEXT FIELD
% ==========================================================

function value = getTextField( ...
    request, ...
    fieldName, ...
    defaultValue)

if ~isfield(request,fieldName) || ...
        isempty(request.(fieldName))

    value = defaultValue;

    return;

end


raw = request.(fieldName);


if ischar(raw)

    value = raw;

elseif isstring(raw)

    value = char(raw(1));

elseif isnumeric(raw) || islogical(raw)

    value = char(string(raw(1)));

else

    value = char(string(raw));

end

end


%% =========================================================
% NUMERIC FIELD
% ==========================================================

function value = getNumericField( ...
    request, ...
    fieldName, ...
    defaultValue)

if ~isfield(request,fieldName) || ...
        isempty(request.(fieldName))

    value = defaultValue;

    return;

end


raw = request.(fieldName);


if isnumeric(raw) || islogical(raw)

    value = double(raw(1));

elseif ischar(raw) || isstring(raw)

    value = str2double(string(raw));

else

    value = defaultValue;

end


if isempty(value) || isnan(value)

    value = defaultValue;

end

end


%% =========================================================
% SQL QUOTING
% ==========================================================

function result = sqlQuote(value)

value = char(string(value));

value = strrep( ...
    value, ...
    "'", ...
    "''");

result = "'" + string(value) + "'";

end


%% =========================================================
% SQL NUMERIC VALUE
% ==========================================================

function result = sqlNumber(value)

if isempty(value) || isnan(value)

    result = "NULL";

    return;

end


result = string( ...
    sprintf( ...
        "%.15g", ...
        double(value)));

end