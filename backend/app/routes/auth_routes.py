from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import select, func
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

from ..db import get_db
from ..models import User, Document
from ..schemas import SignupIn, LoginIn, GoogleIn, TokenOut, UserOut
from ..auth import hash_password, verify_password, create_access_token, get_current_user
from ..config import settings
from ..storage import delete_prefix

router = APIRouter()


@router.post("/signup", response_model=TokenOut)
def signup(payload: SignupIn, db: Session = Depends(get_db)):
    existing = db.execute(select(User).where(User.email == payload.email)).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    if len(payload.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")
    user = User(email=payload.email, password_hash=hash_password(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenOut(access_token=create_access_token(user.id), user_email=user.email)


@router.post("/login", response_model=TokenOut)
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.execute(select(User).where(User.email == payload.email)).scalar_one_or_none()
    if not user or not user.password_hash or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    return TokenOut(access_token=create_access_token(user.id), user_email=user.email)


@router.post("/google", response_model=TokenOut)
def google_signin(payload: GoogleIn, db: Session = Depends(get_db)):
    audiences = settings.google_audiences
    if not audiences:
        raise HTTPException(status_code=503, detail="Google sign-in not configured")
    info = None
    last_err = None
    for aud in audiences:
        try:
            info = google_id_token.verify_oauth2_token(
                payload.id_token, google_requests.Request(), aud
            )
            break
        except ValueError as e:
            last_err = e
            continue
    if info is None:
        raise HTTPException(status_code=401, detail=f"Invalid Google token: {last_err}")
    if not info.get("email_verified"):
        raise HTTPException(status_code=401, detail="Google email not verified")
    email = info["email"]
    sub = info["sub"]
    user = db.execute(select(User).where(User.google_sub == sub)).scalar_one_or_none()
    if not user:
        user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
        if user:
            user.google_sub = sub
        else:
            user = User(email=email, google_sub=sub)
            db.add(user)
        db.commit()
        db.refresh(user)
    return TokenOut(access_token=create_access_token(user.id), user_email=user.email)


@router.get("/me", response_model=UserOut)
def get_me(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    count = db.execute(
        select(func.count(Document.id)).where(Document.user_id == user.id)
    ).scalar_one()
    return UserOut(
        id=user.id,
        email=user.email,
        created_at=user.created_at,
        document_count=count,
    )


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    user_id = user.id
    db.delete(user)
    db.commit()
    delete_prefix(f"users/{user_id}/")
    return None
