"""POST/GET /api/screenings persistence tests."""

SAVE_URL = "/api/screenings"
LIST_URL = "/api/screenings"


def test_save_screening_ok(client, make_screening_payload):
    response = client.post(SAVE_URL, json=make_screening_payload())
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "success"
    screening_id = body["screeningId"]
    assert screening_id.startswith("JN-20") and screening_id[7] == "-"
    assert body["risk"] == "Low"
    assert body["screeningStatus"] == "Completed"


def test_save_screening_second_record_increments(client, make_screening_payload):
    client.post(SAVE_URL, json=make_screening_payload("P001"))
    client.post(SAVE_URL, json=make_screening_payload("P002"))
    ids = [d["id"] for d in client.get(LIST_URL).json()["screeningHistory"]]
    assert len(ids) == 2
    assert ids[0].endswith("-002") or ids[1].endswith("-002")


def test_save_screening_derives_high_risk(client, make_screening_payload):
    payload = make_screening_payload("P003")
    payload["screening"]["predictedClass"] = "Moderate"
    payload["screening"]["referralStatus"] = "REFERABLE DR"
    body = client.post(SAVE_URL, json=payload).json()
    assert body["risk"] == "High"
    assert body["screeningStatus"] == "Requires Review"


def test_save_screening_pending_when_quality_poor(client, make_screening_payload):
    payload = make_screening_payload("P004")
    payload["screening"]["qualityStatus"] = "Poor"
    body = client.post(SAVE_URL, json=payload).json()
    assert body["screeningStatus"] == "Pending"


def test_save_screening_missing_patient_validation(client):
    response = client.post(
        SAVE_URL,
        json={
            "patient": {"patientId": "", "name": "X"},
            "screening": {},
        },
    )
    assert response.status_code == 422


def test_save_screening_missing_screening_fields(client, make_screening_payload):
    response = client.post(
        SAVE_URL,
        json={"patient": make_screening_payload()["patient"]},
    )
    assert response.status_code == 422


def test_list_screenings_empty(client):
    body = client.get(LIST_URL).json()
    assert body["count"] == 0
    assert body["screeningHistory"] == []


def test_list_screenings_after_save(client, make_screening_payload):
    client.post(SAVE_URL, json=make_screening_payload("P001"))
    body = client.get(LIST_URL).json()
    assert body["count"] == 1
    row = body["screeningHistory"][0]
    assert row["patient"] == "Test Patient"
    assert row["result"] == "NoDR"
    assert row["risk"] == "Low"
    assert "status" in row