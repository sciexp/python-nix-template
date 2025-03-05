"""Tests for main module."""

from expression import Error, Ok

from pnt_functional.main import create_greeting, greet, validate_name


def test_validate_name_valid():
    """Test name validation with valid input."""
    assert validate_name("alice") == Ok("Alice")
    assert validate_name(" bob ") == Ok("Bob")


def test_validate_name_invalid():
    """Test name validation with invalid input."""
    assert validate_name("") == Error("Name cannot be empty")
    assert validate_name(" ") == Error("Name cannot be empty")
    assert validate_name("a") == Error("Name must be at least 2 characters")
    assert validate_name("x" * 51) == Error("Name must be at most 50 characters")


def test_create_greeting_valid():
    """Test greeting creation with valid input."""
    assert create_greeting("alice") == Ok("Hello, Alice!")
    assert create_greeting(" bob ") == Ok("Hello, Bob!")


def test_create_greeting_invalid():
    """Test greeting creation with invalid input."""
    result = create_greeting("")
    assert result.is_error()

    result = create_greeting("a")
    assert result.is_error()


def test_greet_default():
    """Test greet function with default argument."""
    result = greet()
    assert result == "Hello, World!"


def test_greet_custom():
    """Test greet function with custom name."""
    result = greet("Alice")
    assert result == "Hello, Alice!"


def test_greet_invalid():
    """Test greet function with invalid input."""
    result = greet("a")
    assert result == "This is supposed to be a hello world program, but it failed."
