#!/usr/bin/env python3
import argparse
import functools

import python_native


def main() -> None:
    parser = argparse.ArgumentParser(description="Factorize a number")
    parser.add_argument("n", type=int, help="The number to factorize")
    args = parser.parse_args()
    n = args.n
    factors = python_native.factor(n)
    print(f"Factors of {n}: {factors}")
    check = functools.reduce(lambda x, y: x * y, factors, 1)
    print(f"Check: {check} == {n}: {check == n}")


if __name__ == "__main__":
    main()
