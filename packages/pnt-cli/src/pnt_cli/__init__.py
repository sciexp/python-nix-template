"""pnt-cli: CLI package with Rust extension module."""

from pnt_cli._native import add, greet

__all__ = ["add", "greet"]


def main() -> None:
    """CLI entrypoint exercising native pyo3 bindings."""
    import sys

    args = sys.argv[1:]
    if args and args[0] == "add" and len(args) == 3:
        result = add(int(args[1]), int(args[2]))
        print(result)
    else:
        name = args[0] if args else "world"
        print(greet(name))
