import pytest

import python_rust


def test_factor() -> None:
    assert python_rust.factor(12) == [2, 2, 3]


def test_factor_edge_cases() -> None:
    assert python_rust.factor(0) == []
    assert python_rust.factor(1) == []


def test_factor_negative() -> None:
    with pytest.raises(OverflowError):
        python_rust.factor(-5)


def test_factor_too_large() -> None:
    with pytest.raises(OverflowError):
        python_rust.factor(2**64)


def test_factor_float() -> None:
    with pytest.raises(TypeError):
        python_rust.factor(12.0)  # type: ignore[arg-type]


def test_factor_index() -> None:
    # Objects with __index__ (e.g. NumPy integers) are accepted like int
    class Twelve:
        def __index__(self) -> int:
            return 12

    assert python_rust.factor(Twelve()) == [2, 2, 3]  # type: ignore[arg-type]
