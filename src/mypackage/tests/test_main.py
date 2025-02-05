"""Tests for main module."""

from mypackage.main import greet


def test_greet_default():
    """Test greet function with default argument."""
    assert greet() == "Hello, World!"


def test_greet_custom():
    """Test greet function with custom name."""
    assert greet("Python") == "Hello, Python!"
