"""Package validation — every bad package gets a reason code, never a crash.

Rejection reasons (checked in this order):
- MISSING_DIMENSIONS: any of lengthIn/widthIn/heightIn absent or null
- TYPE_ERROR:         a dimension (or weight) is not interpretable as a number
- INVALID_DIMENSIONS: a dimension is zero or negative
- OUT_OF_RANGE:       any dimension > 1,000 in, or weight > 5,000 lbs
"""

from typing import Any, Dict, Optional, Tuple

DIMENSION_FIELDS = ("lengthIn", "widthIn", "heightIn")
MAX_DIMENSION_IN = 1_000
MAX_WEIGHT_LBS = 5_000


def _as_number(value: Any) -> Optional[float]:
    """Coerce a JSON value to float, returning None when it isn't numeric.

    Booleans are deliberately not numbers here: `"lengthIn": true` is a
    type error, not a 1-inch package.
    """
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except (ValueError, AttributeError):
            return None
    return None


def validate_package(package: Dict[str, Any]) -> Tuple[Optional[str], Optional[Dict[str, float]]]:
    """Validate a raw package dict.

    Returns (rejection_reason, dims). Exactly one side is set:
    a valid package yields (None, {"lengthIn": .., "widthIn": .., "heightIn": ..}),
    an invalid one yields (reason_code, None).
    """
    if not isinstance(package, dict) or not package:
        return "MISSING_DIMENSIONS", None

    raw = {f: package.get(f) for f in DIMENSION_FIELDS}
    if any(v is None for v in raw.values()):
        return "MISSING_DIMENSIONS", None

    dims: Dict[str, float] = {}
    for field, value in raw.items():
        number = _as_number(value)
        if number is None:
            return "TYPE_ERROR", None
        dims[field] = number

    if any(v <= 0 for v in dims.values()):
        return "INVALID_DIMENSIONS", None

    if any(v > MAX_DIMENSION_IN for v in dims.values()):
        return "OUT_OF_RANGE", None

    weight_raw = package.get("weightLbs")
    if weight_raw is not None:
        weight = _as_number(weight_raw)
        if weight is None:
            return "TYPE_ERROR", None
        if weight > MAX_WEIGHT_LBS:
            return "OUT_OF_RANGE", None

    return None, dims
