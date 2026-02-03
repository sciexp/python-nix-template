/// Greet a user by name.
pub fn greet(name: &str) -> String {
    format!("Hello, {name}! (from Rust)")
}

/// Add two unsigned integers.
pub fn add(a: u64, b: u64) -> u64 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_greet() {
        assert_eq!(greet("world"), "Hello, world! (from Rust)");
    }

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
    }
}
