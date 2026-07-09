"""Routing category tests, including exact boundary values and the
KAN-20 ENABLE_GIGANTIC_CATEGORY toggle behavior."""

import pytest

from app.routing import categorize, compute_volume


class TestComputeVolume:
    def test_simple_volume(self) -> None:
        assert compute_volume({"lengthIn": 10, "widthIn": 5, "heightIn": 2}) == 100

    def test_fractional_dimensions(self) -> None:
        assert compute_volume({"lengthIn": 2.5, "widthIn": 4, "heightIn": 10}) == 100


class TestCategorizeToggleOff:
    """Baseline behavior — must be identical to pre-Gigantic routing."""

    @pytest.mark.parametrize(
        "volume,expected",
        [
            (1, "small"),
            (999, "small"),
            (999.99, "small"),
            (1_000, "medium"),  # exact boundary → upper category
            (1_001, "medium"),
            (7_999, "medium"),
            (7_999.99, "medium"),
            (8_000, "large"),  # exact boundary → upper category
            (8_001, "large"),
            (19_999, "large"),
            (20_000, "large"),  # toggle off: no gigantic, stays large
            (250_000, "large"),
        ],
    )
    def test_category_boundaries(self, volume: float, expected: str) -> None:
        assert categorize(volume, gigantic_enabled=False) == expected

    def test_default_is_toggle_off(self) -> None:
        assert categorize(20_000) == "large"


class TestCategorizeToggleOn:
    """KAN-20 behavior — Large is capped at 19,999; >= 20,000 is Gigantic."""

    @pytest.mark.parametrize(
        "volume,expected",
        [
            (999, "small"),
            (1_000, "medium"),
            (7_999, "medium"),
            (8_000, "large"),
            (19_999, "large"),
            (19_999.99, "large"),
            (20_000, "gigantic"),  # exact boundary → upper category
            (20_001, "gigantic"),
            (250_000, "gigantic"),
        ],
    )
    def test_category_boundaries(self, volume: float, expected: str) -> None:
        assert categorize(volume, gigantic_enabled=True) == expected

    def test_toggle_only_affects_large_and_up(self) -> None:
        """Small/medium routing is untouched by the toggle."""
        for volume in (5, 999, 1_000, 4_500, 7_999):
            assert categorize(volume, gigantic_enabled=False) == categorize(
                volume, gigantic_enabled=True
            )
