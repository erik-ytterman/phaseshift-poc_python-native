#!/usr/bin/env python3
import argparse
import math

import python_native


def main() -> None:
    parser = argparse.ArgumentParser(description="Factorize a number")
    parser.add_argument("n", type=int, help="The number to factorize (2 <= n < 2**64)")
    args = parser.parse_args()
    n = args.n
    if not 2 <= n < 2**64:
        parser.error(f"n must be in the range 2 <= n < 2**64, got {n}")
    factors = python_native.factor(n)
    print(f"Factors of {n}: {factors}")
    check = math.prod(factors)
    print(f"Check: {check} == {n}: {check == n}")


if __name__ == "__main__":
    main()
