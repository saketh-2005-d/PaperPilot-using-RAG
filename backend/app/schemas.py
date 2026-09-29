from datetime import datetime
from typing import Any
from pydantic import BaseModel, EmailStr


class SignupIn(BaseModel):
    email: EmailStr
    password: str


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class GoogleIn(BaseModel):
    id_token: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_email: EmailStr


class UserOut(BaseModel):
    id: int
    email: EmailStr
    created_at: datetime
    document_count: int

    class Config:
        from_attributes = True


class DocumentOut(BaseModel):
    id: int
    title: str
    page_count: int
    status: str
    summary_tldr: str
    sections: list[dict[str, Any]]
    error: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class DocumentListItem(BaseModel):
    id: int
    title: str
    page_count: int
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class ChatIn(BaseModel):
    message: str


class Citation(BaseModel):
    section: str
    page_start: int
    page_end: int


class ChatOut(BaseModel):
    answer: str
    citations: list[Citation]


class MessageOut(BaseModel):
    id: int
    role: str
    content: str
    citations: list[Citation]
    created_at: datetime

    class Config:
        from_attributes = True
