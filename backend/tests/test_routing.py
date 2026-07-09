"""Routing category tests, including exact boundary values."""

import pytest

from app.routing import categorize, compute_volume


class TestComputeVolume:
    def test_simple_volume(self) -> None:
        assert compute_volume({"lengthIn": 10, "widthIn": 5, "heightIn": 2}) == 100

    def test_fractional_dimensions(self) -> None:
        assert compute_volume({"lengthIn": 2.5, "widthIn": 4, "heightIn": 10}) == 100


class TestCategorize:
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
            (20_000, "large"),  # no gigantic category (yet) — stays large
            (250_000, "large"),
        ],
    )
    def test_category_boundaries(self, volume: float, expected: str) -> None:
        assert categorize(volume) == expected
