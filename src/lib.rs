use pyo3::prelude::*;

fn factor_impl(mut n: u64) -> Vec<u64> {
    let mut factors = Vec::new();
    let mut d = 2;
    while d <= n / d {
        while n.is_multiple_of(d) {
            factors.push(d);
            n /= d;
        }
        d += 1;
    }
    if n > 1 {
        factors.push(n);
    }
    factors
}

/// A Python module implemented in Rust. The name of this module must match
/// the `lib.name` setting in the `Cargo.toml`, else Python will not be able to
/// import the module.
#[pymodule]
mod _core {
    use pyo3::prelude::*;

    /// Return a greeting from the Rust core.
    #[pyfunction]
    fn hello_from_bin() -> String {
        "Hello from python-native!".to_string()
    }

    /// Return the prime factors of `n` in ascending order.
    ///
    /// `n` must be in the range 0 <= n < 2**64; otherwise OverflowError is raised.
    #[pyfunction]
    fn factor(n: u64) -> Vec<u64> {
        super::factor_impl(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn factors() {
        assert_eq!(factor_impl(12), vec![2, 2, 3]);
        assert_eq!(factor_impl(360), vec![2, 2, 2, 3, 3, 5]);
        assert_eq!(factor_impl(97), vec![97]);
    }

    #[test]
    fn edge_cases() {
        assert_eq!(factor_impl(0), Vec::<u64>::new());
        assert_eq!(factor_impl(1), Vec::<u64>::new());
        assert_eq!(
            factor_impl(u64::MAX),
            vec![3, 5, 17, 257, 641, 65537, 6700417]
        );
    }
}
