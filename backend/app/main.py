"""Package Router API.

A local demo service that routes packages into size-category consumers
by dimensional volume, with visible rejection of malformed input.

Run:  uvicorn app.main:app --reload  (from backend/)
"""

import json
from pathlib import Path
from typing import Any, Dict, List, Union

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from . import config
from .consumers import ConsumerRegistry
from .models import ProcessResponse, RoutingResult, ToggleRequest
from .routing import CATEGORIES, categorize, compute_volume
from .validation import validate_package

DATA_FILE = Path(__file__).resolve().parents[2] / "data" / "sample_packages.json"

app = FastAPI(title="Package Router", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

registry = ConsumerRegistry(list(CATEGORIES))


def _summary_fields(package: Dict[str, Any], volume: float) -> Dict[str, Any]:
    """The slice of a routed package the UI shows in consumer logs."""
    return {
        "trackingNumber": str(package.get("trackingNumber", "UNKNOWN")),
        "lengthIn": package.get("lengthIn"),
        "widthIn": package.get("widthIn"),
        "heightIn": package.get("heightIn"),
        "weightLbs": package.get("weightLbs"),
        "volume": volume,
        "serviceType": package.get("serviceType"),
        "destinationCity": package.get("destinationCity"),
    }


def _process_one(package: Any) -> RoutingResult:
    """Validate and route a single raw package, recording the outcome."""
    if not isinstance(package, dict):
        package = {}
    tracking = str(package.get("trackingNumber") or "UNKNOWN")

    reason, dims = validate_package(package)
    if reason is not None:
        registry.reject(
            {
                "trackingNumber": tracking,
                "reason": reason,
                "lengthIn": package.get("lengthIn"),
                "widthIn": package.get("widthIn"),
                "heightIn": package.get("heightIn"),
                "weightLbs": package.get("weightLbs"),
            }
        )
        return RoutingResult(trackingNumber=tracking, status="rejected", reason=reason)

    volume = compute_volume(dims)
    category = categorize(volume)
    registry.deliver(category, _summary_fields(package, volume))
    return RoutingResult(
        trackingNumber=tracking, status="routed", category=category, volume=volume
    )


@app.post("/packages/process", response_model=ProcessResponse)
def process_packages(payload: Union[Dict[str, Any], List[Any]]) -> ProcessResponse:
    """Process one package (object) or a batch (array)."""
    packages = payload if isinstance(payload, list) else [payload]
    results = [_process_one(p) for p in packages]
    routed = sum(1 for r in results if r.status == "routed")
    return ProcessResponse(results=results, routed=routed, rejected=len(results) - routed)


@app.post("/packages/process-all", response_model=ProcessResponse)
def process_all() -> ProcessResponse:
    """Process the entire bundled sample dataset."""
    if not DATA_FILE.exists():
        raise HTTPException(status_code=500, detail="sample_packages.json not found")
    packages = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    results = [_process_one(p) for p in packages]
    routed = sum(1 for r in results if r.status == "routed")
    return ProcessResponse(results=results, routed=routed, rejected=len(results) - routed)


@app.get("/packages/sample")
def sample_packages() -> List[Dict[str, Any]]:
    """Return the raw sample dataset (the UI animates from this)."""
    if not DATA_FILE.exists():
        raise HTTPException(status_code=500, detail="sample_packages.json not found")
    return json.loads(DATA_FILE.read_text(encoding="utf-8"))


@app.get("/consumers/state")
def consumers_state() -> Dict[str, Any]:
    """Everything each consumer has received, plus rejections."""
    return registry.state()


@app.get("/config")
def get_config() -> Dict[str, Any]:
    """Current feature toggles."""
    return {"toggles": config.get_toggles()}


@app.post("/config/toggle")
def post_toggle(body: ToggleRequest) -> Dict[str, Any]:
    """Set (or flip, when value omitted) a named feature toggle."""
    try:
        value = (
            config.flip_toggle(body.name)
            if body.value is None
            else config.set_toggle(body.name, body.value)
        )
    except KeyError:
        raise HTTPException(status_code=404, detail=f"Unknown toggle: {body.name}")
    return {"name": body.name, "value": value, "toggles": config.get_toggles()}


@app.post("/reset")
def reset() -> Dict[str, str]:
    """Clear all consumer and rejected state."""
    registry.reset()
    return {"status": "reset"}
