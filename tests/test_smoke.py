import python_rust


def test_hello() -> None:
    assert isinstance(python_rust.hello(), str)
