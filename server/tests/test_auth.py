from server.auth import create_token, verify_token


def test_create_and_verify_token():
    token = create_token("admin")
    payload = verify_token(token)
    assert payload is not None
    assert payload["sub"] == "admin"


def test_invalid_token_returns_none():
    payload = verify_token("invalid.token.here")
    assert payload is None
