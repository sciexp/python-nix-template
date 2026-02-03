from pnt_cli import add, greet


def test_greet() -> None:
    result = greet("world")
    assert result == "Hello, world! (from Rust)"


def test_add() -> None:
    assert add(2, 3) == 5
    assert add(0, 0) == 0
