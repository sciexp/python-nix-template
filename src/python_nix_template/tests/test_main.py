# TODO: restore absolute imports when
# https://github.com/juspay/omnix/issues/425
# is resolved
# from python_nix_template import main
from .. import main


def test_main(capsys):
    """Test that the main function prints the expected greeting."""
    main()
    captured = capsys.readouterr()
    assert "Hello from python-nix-template!" in captured.out


def test_main_returns_none():
    """Test that the main function returns None."""
    result = main()
    assert result is None
