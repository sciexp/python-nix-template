"""Main module for mypackage."""


def greet(name: str = "World") -> str:
    """Return a greeting message.

    Args:
        name: Name to greet. Defaults to "World".

    Returns:
        A greeting message.
    """
    return f"Hello, {name}!" 