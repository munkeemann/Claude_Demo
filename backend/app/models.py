"""API response models.

Incoming packages are intentionally *not* strictly modeled: the whole
point of the demo is that malformed payloads (missing fields, strings
where numbers belong) reach the validator and come back as visible
rejections instead of framework-level 422s.
"""

from typing import List, Optional

from pydantic import BaseModel


class RoutingResult(BaseModel):
    """Outcome of processing a single package."""

    trackingNumber: str
    status: str  # "routed" | "rejected"
    category: Optional[str] = None  # set when routed
    volume: Optional[float] = None  # in³, set when routed
    reason: Optional[str] = None  # rejection reason code, set when rejected


class ProcessResponse(BaseModel):
    """Outcome of a process call (single package or batch)."""

    results: List[RoutingResult]
    routed: int
    rejected: int


class ToggleRequest(BaseModel):
    """Body for POST /config/toggle."""

    name: str
    value: Optional[bool] = None  # omit to flip
