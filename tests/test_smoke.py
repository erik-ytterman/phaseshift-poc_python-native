import python_native


def test_hello() -> None:
    assert isinstance(python_native.hello(), str)
