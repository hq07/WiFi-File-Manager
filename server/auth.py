from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt

SECRET_KEY = "wifi-file-manager-secret-change-in-production"
ALGORITHM = "HS256"
TOKEN_EXPIRE_HOURS = 24


def create_token(username: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRE_HOURS)
    return jwt.encode({"sub": username, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> dict | None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None
