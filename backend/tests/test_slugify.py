import pytest

from app.main import slugify


@pytest.mark.parametrize(
    "word, expected",
    [
        ("ice cream", "ice-cream"),
        ("I", "i"),
        ("  Apple! ", "apple"),
        ("Juice", "juice"),
        ("hello---world", "hello-world"),
        ("???", "card"),
        ("", "card"),
    ],
)
def test_slugify(word, expected):
    assert slugify(word) == expected
