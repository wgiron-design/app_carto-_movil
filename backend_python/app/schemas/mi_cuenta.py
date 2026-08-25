import re
from pydantic import BaseModel, EmailStr, Field, field_validator

class UpdateUsernameRequest(BaseModel):
    new_username: str = Field(..., min_length=3, max_length=50, description="Nuevo nombre de usuario")

    @field_validator("new_username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[a-zA-Z0-9_.-]+$", v):
            raise ValueError("El nombre de usuario solo puede contener letras, números, guiones y puntos.")
        return v

class UpdateEmailRequest(BaseModel):
    new_email: EmailStr

class UpdatePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=5)
    confirm_password: str = Field(..., min_length=5)
