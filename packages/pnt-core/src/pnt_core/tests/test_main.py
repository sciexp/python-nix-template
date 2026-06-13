# https://github.com/juspay/omnix/issues/425: use relative import until resolved
# from pnt_core import main
import pytest

from .. import main


def test_main(capsys: pytest.CaptureFixture[str]):
    """Test that the main function prints the expected greeting."""
    main()
    captured = capsys.readouterr()
    assert "Hello from pnt-core!" in captured.out


def test_main_returns_none():
    """Test that the main function returns None."""
    result = main()
    assert result is None
