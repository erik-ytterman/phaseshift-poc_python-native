use pyo3::prelude::*;

/// A Python module implemented in Rust. The name of this module must match
/// the `lib.name` setting in the `Cargo.toml`, else Python will not be able to
/// import the module.
#[pymodule]
mod _core {
    use pyo3::prelude::*;

    #[pyfunction]
    fn hello_from_bin() -> String {
        "Hello from python-native!".to_string()
    }

    #[pyfunction]
    fn factor(n: u64) -> Vec<u64> {
        let mut factors = Vec::new();
        let mut i = 2;
        let mut n = n;
        while i * i <= n {
            while n.is_multiple_of(i) {
                factors.push(i);
                n /= i;
            }
            i += 1;
        }
        if n > 1 {
            factors.push(n);
        }
        factors
    }
}
