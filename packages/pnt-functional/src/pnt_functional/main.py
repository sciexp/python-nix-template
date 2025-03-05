"""Main module for pnt_functional demonstrating functional programming patterns."""

from beartype import beartype
from expression import Error, Ok, Result


@beartype
def validate_name(name: str) -> Result[str, Error]:
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
def create_greeting(name: str) -> Result[str, Error]:
    """Create a greeting message.

    Args:
        name: Name to greet

    Returns:
        Result with greeting message or error message
    """
    return validate_name(name).bind(lambda n: Ok(f"Hello, {n}!"))


@beartype
def greet(name: str = "World") -> str:
    """Greet someone by name.

    Args:
        name: Optional name to greet. Defaults to "World".

    Returns:
        Greeting message or error message
    """
    greeting = create_greeting(name)

    match greeting:
        case Result(tag="ok"):
            return greeting.ok
        case Result(tag="error"):
            print(
                f"Verify you've respected the input constraints:\n\n{greeting.error}\n"
            )
            return "This is supposed to be a hello world program, but it failed."
        case _:
            return "The return type is not a Result."
