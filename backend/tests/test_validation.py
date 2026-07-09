"""Every rejection path, plus the happy path."""

import pytest

from app.validation import validate_package


def _pkg(**overrides):
    base = {"trackingNumber": "PKR-1", "lengthIn": 10, "widthIn": 10, "heightIn": 10, "weightLbs": 5}
    base.update(overrides)
    return base


class TestValidPackages:
    def test_valid_package_returns_dims(self) -> None:
        reason, dims = validate_package(_pkg())
        assert reason is None
        assert dims == {"lengthIn": 10.0, "widthIn": 10.0, "heightIn": 10.0}

    def test_numeric_strings_are_coerced(self) -> None:
        reason, dims = validate_package(_pkg(lengthIn="12.5"))
        assert reason is None
        assert dims["lengthIn"] == 12.5

    def test_missing_weight_is_fine(self) -> None:
        pkg = _pkg()
        del pkg["weightLbs"]
        reason, _ = validate_package(pkg)
        assert reason is None


class TestMissingDimensions:
    @pytest.mark.parametrize("field", ["lengthIn", "widthIn", "heightIn"])
    def test_absent_dimension(self, field: str) -> None:
        pkg = _pkg()
        del pkg[field]
        assert validate_package(pkg)[0] == "MISSING_DIMENSIONS"

    def test_null_dimension(self) -> None:
        assert validate_package(_pkg(heightIn=None))[0] == "MISSING_DIMENSIONS"

    def test_empty_package(self) -> None:
        assert validate_package({})[0] == "MISSING_DIMENSIONS"

    def test_non_dict(self) -> None:
        assert validate_package(None)[0] == "MISSING_DIMENSIONS"  # type: ignore[arg-type]


class TestInvalidDimensions:
    def test_zero_dimension(self) -> None:
        assert validate_package(_pkg(widthIn=0))[0] == "INVALID_DIMENSIONS"

    def test_negative_dimension(self) -> None:
        assert validate_package(_pkg(lengthIn=-4))[0] == "INVALID_DIMENSIONS"

    def test_negative_numeric_string(self) -> None:
        assert validate_package(_pkg(heightIn="-2"))[0] == "INVALID_DIMENSIONS"


class TestTypeErrors:
    def test_word_dimension(self) -> None:
        assert validate_package(_pkg(lengthIn="twelve"))[0] == "TYPE_ERROR"

    def test_boolean_dimension(self) -> None:
        assert validate_package(_pkg(widthIn=True))[0] == "TYPE_ERROR"

    def test_list_dimension(self) -> None:
        assert validate_package(_pkg(heightIn=[10]))[0] == "TYPE_ERROR"

    def test_non_numeric_weight(self) -> None:
        assert validate_package(_pkg(weightLbs="heavy"))[0] == "TYPE_ERROR"


class TestOutOfRange:
    def test_dimension_over_1000(self) -> None:
        assert validate_package(_pkg(lengthIn=1001))[0] == "OUT_OF_RANGE"

    def test_dimension_exactly_1000_is_allowed(self) -> None:
        assert validate_package(_pkg(lengthIn=1000))[0] is None

    def test_weight_over_5000(self) -> None:
        assert validate_package(_pkg(weightLbs=5001))[0] == "OUT_OF_RANGE"

    def test_weight_exactly_5000_is_allowed(self) -> None:
        assert validate_package(_pkg(weightLbs=5000))[0] is None


class TestPrecedence:
    def test_missing_beats_type_error(self) -> None:
        pkg = _pkg(widthIn="junk")
        del pkg["lengthIn"]
        assert validate_package(pkg)[0] == "MISSING_DIMENSIONS"

    def test_type_error_beats_out_of_range(self) -> None:
        assert validate_package(_pkg(lengthIn="junk", weightLbs=9999))[0] == "TYPE_ERROR"
