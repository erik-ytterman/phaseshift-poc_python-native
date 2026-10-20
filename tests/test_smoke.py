import python_native


def test_hello() -> None:
    assert isinstance(python_native.hello(), str)

def test_factorize() -> None:
    assert isinstance(python_native.factorize(12), list)
    assert python_native.factorize(12) == [2, 2, 3]
