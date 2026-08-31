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
    asignado_por: Optional[str] = None
    asignado_por_username: Optional[str] = None
    asignado_en: Optional[datetime] = None

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
    supervisores: List[dict] = []
    selected_supervisor_id: Optional[str] = None
    cartografos: List[dict] = []
    selected_cartografo_id: Optional[str] = None
    upms_disponibles: List[UpmSimpleItem] = []
    upms_asignadas: List[UpmSimpleItem] = []

class AsignarUpmCartografoRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)
    id_cartografo: str

class DesasignarUpmCartografoRequest(BaseModel):
    upm_ids: List[str] = Field(..., min_length=1)
    id_cartografo: str
