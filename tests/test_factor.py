import pytest

import python_native


def test_factor() -> None:
    assert python_native.factor(12) == [2, 2, 3]


def test_factor_edge_cases() -> None:
    assert python_native.factor(0) == []
    assert python_native.factor(1) == []


def test_factor_negative() -> None:
    with pytest.raises(OverflowError):
        python_native.factor(-5)


def test_factor_too_large() -> None:
    with pytest.raises(OverflowError):
        python_native.factor(2**64)


def test_factor_float() -> None:
    with pytest.raises(TypeError):
        python_native.factor(12.0)  # type: ignore[arg-type]
