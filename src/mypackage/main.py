"""Main module for mypackage demonstrating functional programming patterns."""

from beartype import beartype
from beartype.typing import Generator, Optional
from expression import Error, Ok, Result, effect


@beartype
def validate_name(name: str) -> Result[str, str]:
    """Validate a name.

    Args:
        name: Name to validate

    Returns:
        Result with validated name or error message
    """
    name = name.strip()
    if not name:
        return Error("Name cannot be empty")
    if len(name) < 2:
        return Error("Name must be at least 2 characters")
    if len(name) > 50:
        return Error("Name must be at most 50 characters")
    return Ok(name.capitalize())


@beartype
def create_greeting(name: str) -> Result[str, str]:
    """Create a greeting message.

    Args:
        name: Name to greet

    Returns:
        Result with greeting message or error message
    """
    return validate_name(name).bind(lambda n: Ok(f"Hello, {n}!"))


@effect.result[str, ValueError]()
def greet(name: Optional[str] = None) -> Generator[Optional[str], str, Optional[str]]:
    """Greet someone by name.

    Args:
        name: Optional name to greet. Defaults to "World".

    Returns:
        Generator yielding Optional[str], receiving str, and returning Optional[str]
    """
    result = yield from create_greeting(name or "World")
    return result
