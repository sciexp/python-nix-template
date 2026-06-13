from importlib import metadata

try:
    __version__ = metadata.version(__package__ or "")
except metadata.PackageNotFoundError:
    __version__ = "unknown"

del metadata


def main() -> None:
    print("Hello from pnt-core!")
