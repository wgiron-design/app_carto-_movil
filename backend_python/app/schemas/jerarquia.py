from pydantic import BaseModel, Field
from typing import List, Optional

class HierarchicalUserItem(BaseModel):
    id: str
    username: str
    email: str
    role: str
    id_supervisor: Optional[str] = None
    supervisor_username: Optional[str] = None
    subordinados_count: int = 0

class JerarquiaResponse(BaseModel):
    supervisores: List[HierarchicalUserItem]
    monitores_sin_supervisor: List[HierarchicalUserItem]
    cartografos_sin_supervisor: List[HierarchicalUserItem]
    monitores_asignados: List[HierarchicalUserItem]
    cartografos_asignados: List[HierarchicalUserItem]

class AsignarSupervisorRequest(BaseModel):
    user_ids: List[str] = Field(..., min_length=1)
    id_supervisor: Optional[str] = None # Si es None, desasigna
