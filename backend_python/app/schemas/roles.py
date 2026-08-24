from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class RoleConfigResponse(BaseModel):
    id: str
    descripcion: str
    activo: bool
    total_usuarios: int = 0
    updated_at: datetime

class RoleUpdateConfig(BaseModel):
    descripcion: Optional[str] = Field(None, min_length=2, max_length=255)
    activo: Optional[bool] = None
