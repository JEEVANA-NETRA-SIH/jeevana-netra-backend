"""GET /api/patients and GET /api/patients/{id} tests."""

PATIENTS_URL = "/api/patients"


def _seed(client, make_screening_payload, patient_id="P100"):
    return client.post("/api/screenings", json=make_screening_payload(patient_id))


def test_patients_empty(client):
    body = client.get(PATIENTS_URL).json()
    assert body["count"] == 0
    assert body["patientRecords"] == []


def test_patients_after_save(client, make_screening_payload):
    _seed(client, make_screening_payload)
    body = client.get(PATIENTS_URL).json()
    assert body["count"] == 1
    record = body["patientRecords"][0]
    assert record["id"] == "P100"
    assert record["name"] == "Test Patient"
    assert record["age"] == 45
    assert record["gender"] == "F"
    assert record["result"] == "NoDR"


def test_patient_not_found(client):
    response = client.get(f"{PATIENTS_URL}/UNKNOWN")
    assert response.status_code == 404


def test_patient_history(client, make_screening_payload):
    _seed(client, make_screening_payload)
    body = client.get(f"{PATIENTS_URL}/P100").json()
    assert body["patientId"] == "P100"
    assert body["count"] == 1
    record = body["history"][0]
    assert record["screeningId"].startswith("JN-20")
    assert record["result"] == "NoDR"
    assert record["probabilities"]["NoDR"] == 87.5
    assert record["lesionEvidence"] == []


def test_patient_added_after_multiple_seed(client, make_screening_payload):
    _seed(client, make_screening_payload, "P100")
    _seed(client, make_screening_payload, "P200")
    body = client.get(PATIENTS_URL).json()
    ids = {r["id"] for r in body["patientRecords"]}
    assert ids == {"P100", "P200"}