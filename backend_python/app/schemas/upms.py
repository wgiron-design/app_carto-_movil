from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class UpmSimpleItem(BaseModel):
    id: str
    nombre: str
    codigo_upm: Optional[str] = None
    id_supervisor: Optional[str] = None
    supervisor_username: Optional[str] = None
    cartografos_count: int = 0

class AsignacionUpmSupervisorResponse(BaseModel):
    supervisores: List[dict]
    upms_disponibles: List[UpmSimpleItem]
    upms_asignadas: List[UpmSimpleItem]

class AsignarUpmSupervisorRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)
    id_supervisor: str

class DesasignarUpmSupervisorRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)

class AsignacionUpmCartografoResponse(BaseModel):
    cartografos: List[dict]
    upms_disponibles: List[UpmSimpleItem]
    upms_asignadas: List[UpmSimpleItem]

class AsignarUpmCartografoRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)
    id_cartografo: str

class DesasignarUpmCartografoRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)
    id_cartografo: str
