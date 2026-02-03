use pyo3::prelude::*;

/// Greet a user by name, returning a string from Rust.
#[pyfunction]
fn greet(name: &str) -> String {
    pnt_cli_core::greet(name)
}

/// Add two unsigned integers.
#[pyfunction]
fn add(a: u64, b: u64) -> u64 {
    pnt_cli_core::add(a, b)
}

/// Native extension module for pnt-cli.
#[pymodule(name = "_native")]
fn pnt_cli_native(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(greet, m)?)?;
    m.add_function(wrap_pyfunction!(add, m)?)?;
    Ok(())
}
