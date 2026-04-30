from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class LoginRequest(BaseModel):
    email: EmailStr
    pin: str = Field(min_length=4, max_length=4, pattern=r"^\d{4}$")


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class ChatResponse(BaseModel):
    reply: str


class ConversationMessageResponse(BaseModel):
    role: str
    content: str
    created_at: datetime


class ConversationHistoryResponse(BaseModel):
    messages: list[ConversationMessageResponse]
