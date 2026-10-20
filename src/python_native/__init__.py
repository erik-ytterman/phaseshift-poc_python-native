from python_native._core import factor, hello_from_bin


def hello() -> str:
    return hello_from_bin()

def factorize(n: int) -> list[int]:
    return factor(n)
