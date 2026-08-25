from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional
from enum import Enum
from datetime import datetime
import re

class RoleEnum(str, Enum):
    ADMIN = "admin"
    ADMINISTRADOR = "administrador"
    MONITOR = "monitor"
    SUPERVISOR = "supervisor"
    CARTOGRAFO = "cartografo"
    CONSULTA = "consulta"
    GERENTE = "gerente"

class UserRegister(BaseModel):
    username: str = Field(..., min_length=3, max_length=50, description="Nombre de usuario único")
    email: EmailStr = Field(..., description="Correo electrónico válido")
    password: str = Field(..., min_length=5, description="Contraseña con mínimo 5 caracteres")

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[a-zA-Z0-9_.-]+$", v):
            raise ValueError("El nombre de usuario solo puede contener letras, números, guiones y puntos.")
        return v

class UserLogin(BaseModel):
    username: str = Field(..., description="Nombre de usuario o correo electrónico")
    password: str = Field(..., description="Contraseña")

class ForgotPasswordRequest(BaseModel):
    username: str = Field(..., description="Nombre de usuario")
    email: EmailStr = Field(..., description="Correo electrónico asociado a la cuenta")

class ResetPasswordRequest(BaseModel):
    token: str = Field(..., description="Token de recuperación enviado por correo")
    new_password: str = Field(..., min_length=5, description="Nueva contraseña con mínimo 5 caracteres")

class UserUpdateStatus(BaseModel):
    is_active: Optional[bool] = None
    role: Optional[RoleEnum] = None

class UserResponse(BaseModel):
    id: str
    username: str
    email: str
    role: str
    id_cat_rol: Optional[str] = None
    is_active: bool
    created_at: datetime
    last_login_at: Optional[datetime] = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
