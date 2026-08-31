from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator
from typing import Optional, List, Any
from datetime import datetime
import re

class UserAdminCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    password: str = Field(..., min_length=5)
    role: str = "cartografo"
    id_cat_rol: Optional[str] = None
    id_jefe: Optional[str] = None
    id_supervisor: Optional[str] = None
    is_active: bool = True

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip()
        if not re.match(r"^[a-zA-Z0-9_.-]+$", v):
            raise ValueError("El nombre de usuario solo puede contener letras, números, guiones y puntos.")
        return v

    @model_validator(mode="before")
    @classmethod
    def check_id_jefe_or_supervisor(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if not data.get("id_jefe") and data.get("id_supervisor"):
                data["id_jefe"] = data["id_supervisor"]
            elif data.get("id_jefe") and not data.get("id_supervisor"):
                data["id_supervisor"] = data["id_jefe"]
        return data

class UserAdminUpdate(BaseModel):
    email: Optional[EmailStr] = None
    role: Optional[str] = None
    id_cat_rol: Optional[str] = None
    id_jefe: Optional[str] = None
    id_supervisor: Optional[str] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(None, min_length=5)

    @model_validator(mode="before")
    @classmethod
    def check_id_jefe_or_supervisor(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if not data.get("id_jefe") and data.get("id_supervisor"):
                data["id_jefe"] = data["id_supervisor"]
            elif data.get("id_jefe") and not data.get("id_supervisor"):
                data["id_supervisor"] = data["id_jefe"]
        return data

class UserAdminItem(BaseModel):
    id: str
    username: str
    email: str
    role: str
    id_cat_rol: Optional[str] = None
    is_active: bool
    id_jefe: Optional[str] = None
    jefe_username: Optional[str] = None
    # Campos retrocompatibles para clientes que aún leen id_supervisor
    id_supervisor: Optional[str] = None
    supervisor_username: Optional[str] = None
    created_at: datetime
    last_login_at: Optional[datetime] = None

    @model_validator(mode="before")
    @classmethod
    def populate_supervisor_alias(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if "id_jefe" in data and "id_supervisor" not in data:
                data["id_supervisor"] = data["id_jefe"]
            if "jefe_username" in data and "supervisor_username" not in data:
                data["supervisor_username"] = data["jefe_username"]
        return data

class PaginatedUsersResponse(BaseModel):
    items: List[UserAdminItem]
    total: int
    page: int
    page_size: int
    total_pages: int

