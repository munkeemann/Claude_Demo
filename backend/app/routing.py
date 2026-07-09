"""Core routing logic: dimensional volume → size category.

Categories:
    Small:  volume <  1,000 in³
    Medium: 1,000 <= volume < 8,000
    Large:  volume >= 8,000
"""

from typing import Dict

SMALL_MAX = 1_000       # exclusive upper bound for Small
MEDIUM_MAX = 8_000      # exclusive upper bound for Medium

CATEGORIES = ("small", "medium", "large")


def compute_volume(dims: Dict[str, float]) -> float:
    """Dimensional volume in cubic inches (L × W × H)."""
    return dims["lengthIn"] * dims["widthIn"] * dims["heightIn"]


def categorize(volume: float) -> str:
    """Map a volume to its consumer category.

    Boundary semantics: each threshold belongs to the *upper* category
    (exactly 1,000 → medium, exactly 8,000 → large).
    """
    if volume < SMALL_MAX:
        return "small"
    if volume < MEDIUM_MAX:
        return "medium"
    return "large"
