"""A Python package template using Nix and uv."""

from importlib import metadata

from pnt_functional.main import greet

try:
    __version__ = metadata.version(__package__)
except metadata.PackageNotFoundError:
    __version__ = "unknown"

del metadata

__all__ = [
    "greet",
]
