"""Core routing logic: dimensional volume → size category.

Baseline categories:
    Small:  volume <  1,000 in³
    Medium: 1,000 <= volume < 8,000
    Large:  volume >= 8,000

With ENABLE_GIGANTIC_CATEGORY on (KAN-20):
    Large:    8,000 <= volume < 20,000
    Gigantic: volume >= 20,000
"""

from typing import Dict

SMALL_MAX = 1_000       # exclusive upper bound for Small
MEDIUM_MAX = 8_000      # exclusive upper bound for Medium
LARGE_MAX = 20_000      # exclusive upper bound for Large (only when Gigantic is enabled)

CATEGORIES = ("small", "medium", "large", "gigantic")


def compute_volume(dims: Dict[str, float]) -> float:
    """Dimensional volume in cubic inches (L × W × H)."""
    return dims["lengthIn"] * dims["widthIn"] * dims["heightIn"]


def categorize(volume: float, gigantic_enabled: bool = False) -> str:
    """Map a volume to its consumer category.

    Boundary semantics: each threshold belongs to the *upper* category
    (exactly 1,000 → medium, exactly 8,000 → large, exactly 20,000 →
    gigantic when the toggle is on).

    With ``gigantic_enabled`` False this is byte-identical to the
    pre-KAN-20 behavior: everything >= 8,000 is Large.
    """
    if volume < SMALL_MAX:
        return "small"
    if volume < MEDIUM_MAX:
        return "medium"
    if gigantic_enabled and volume >= LARGE_MAX:
        return "gigantic"
    return "large"
