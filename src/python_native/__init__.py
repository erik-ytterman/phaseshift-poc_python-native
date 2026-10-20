from python_native import _core


def hello() -> str:
    """Return a greeting from the Rust core."""
    return _core.hello_from_bin()


def factor(n: int) -> list[int]:
    """Return the prime factors of `n` in ascending order.

    `n` must be in the range 0 <= n < 2**64; otherwise OverflowError is raised.
    0 and 1 have no prime factors and return an empty list.
    """
    return _core.factor(n)
