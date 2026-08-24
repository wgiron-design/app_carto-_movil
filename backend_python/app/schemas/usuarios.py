from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional, List
from datetime import datetime
import re

class UserAdminCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    password: str = Field(..., min_length=5)
    role: str = "cartografo"
    id_cat_rol: Optional[str] = None
    id_supervisor: Optional[str] = None
    is_active: bool = True

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[a-zA-Z0-9_.-]+$", v):
            raise ValueError("El nombre de usuario solo puede contener letras, números, guiones y puntos.")
        return v

class UserAdminUpdate(BaseModel):
    email: Optional[EmailStr] = None
    role: Optional[str] = None
    id_cat_rol: Optional[str] = None
    id_supervisor: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(None, min_length=5)

class UserAdminItem(BaseModel):
    id: str
    username: str
    email: str
    role: str
    id_cat_rol: Optional[str] = None
    is_active: bool
    id_supervisor: Optional[str] = None
    supervisor_username: Optional[str] = None
    created_at: datetime
    last_login_at: Optional[datetime] = None

class PaginatedUsersResponse(BaseModel):
    items: List[UserAdminItem]
    total: int
    page: int
    page_size: int
    total_pages: int
