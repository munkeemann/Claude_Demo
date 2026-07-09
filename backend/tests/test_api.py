"""End-to-end API tests via FastAPI's TestClient."""

import pytest
from fastapi.testclient import TestClient

from app import config
from app.main import app, registry

client = TestClient(app)


@pytest.fixture(autouse=True)
def clean_state():
    """Fresh consumer state and default toggles around every test."""
    registry.reset()
    config.reset_toggles()
    yield
    registry.reset()
    config.reset_toggles()


class TestProcess:
    def test_routes_valid_package(self) -> None:
        r = client.post("/packages/process", json={"trackingNumber": "T-1", "lengthIn": 5, "widthIn": 5, "heightIn": 5})
        assert r.status_code == 200
        body = r.json()
        assert body["routed"] == 1
        assert body["results"][0]["category"] == "small"
        assert body["results"][0]["volume"] == 125

    def test_batch_mixed(self) -> None:
        r = client.post(
            "/packages/process",
            json=[
                {"trackingNumber": "T-1", "lengthIn": 5, "widthIn": 5, "heightIn": 5},
                {"trackingNumber": "T-2", "lengthIn": "bad", "widthIn": 5, "heightIn": 5},
            ],
        )
        body = r.json()
        assert body["routed"] == 1
        assert body["rejected"] == 1
        assert body["results"][1]["reason"] == "TYPE_ERROR"

    def test_rejection_never_500s(self) -> None:
        for payload in [{}, {"lengthIn": -1, "widthIn": 2, "heightIn": 2}, {"lengthIn": 9999, "widthIn": 1, "heightIn": 1}]:
            r = client.post("/packages/process", json=payload)
            assert r.status_code == 200
            assert r.json()["rejected"] == 1


class TestProcessAll:
    def test_all_100_land_somewhere(self) -> None:
        r = client.post("/packages/process-all")
        assert r.status_code == 200
        assert r.json()["routed"] + r.json()["rejected"] == 100

        state = client.get("/consumers/state").json()
        consumer_total = sum(c["count"] for c in state["consumers"].values())
        assert consumer_total + state["rejected"]["count"] == 100

    def test_sample_data_is_all_valid(self) -> None:
        r = client.post("/packages/process-all")
        assert r.json()["rejected"] == 0


class TestConsumersState:
    def test_state_shape(self) -> None:
        client.post("/packages/process", json={"trackingNumber": "T-1", "lengthIn": 20, "widthIn": 20, "heightIn": 20})
        state = client.get("/consumers/state").json()
        assert state["consumers"]["large"]["count"] == 1
        pkg = state["consumers"]["large"]["packages"][0]
        assert pkg["trackingNumber"] == "T-1"
        assert pkg["volume"] == 8000


class TestReset:
    def test_reset_clears_everything(self) -> None:
        client.post("/packages/process-all")
        client.post("/reset")
        state = client.get("/consumers/state").json()
        assert state["totalProcessed"] == 0
        assert state["rejected"]["count"] == 0


class TestConfig:
    def test_unknown_toggle_404s(self) -> None:
        r = client.post("/config/toggle", json={"name": "NOT_A_TOGGLE"})
        assert r.status_code == 404

    def test_gigantic_toggle_defaults_off(self) -> None:
        r = client.get("/config")
        assert r.json()["toggles"]["ENABLE_GIGANTIC_CATEGORY"] is False

    def test_toggle_changes_routing_at_runtime(self) -> None:
        """KAN-20: same package, different lane, no restart."""
        pkg = {"trackingNumber": "T-GIG", "lengthIn": 50, "widthIn": 40, "heightIn": 10}  # 20,000

        r = client.post("/packages/process", json=pkg)
        assert r.json()["results"][0]["category"] == "large"

        client.post("/config/toggle", json={"name": "ENABLE_GIGANTIC_CATEGORY", "value": True})
        r = client.post("/packages/process", json=pkg)
        assert r.json()["results"][0]["category"] == "gigantic"

        # flip without explicit value inverts
        client.post("/config/toggle", json={"name": "ENABLE_GIGANTIC_CATEGORY"})
        r = client.post("/packages/process", json=pkg)
        assert r.json()["results"][0]["category"] == "large"

    def test_gigantic_lane_present_in_state(self) -> None:
        client.post("/config/toggle", json={"name": "ENABLE_GIGANTIC_CATEGORY", "value": True})
        client.post("/packages/process", json={"trackingNumber": "T-1", "lengthIn": 40, "widthIn": 40, "heightIn": 40})
        state = client.get("/consumers/state").json()
        assert state["consumers"]["gigantic"]["count"] == 1
