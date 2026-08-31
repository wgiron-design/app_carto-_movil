from pydantic import BaseModel, Field, model_validator
from typing import List, Optional, Any

class HierarchicalUserItem(BaseModel):
    id: str
    username: str
    email: str
    role: str
    id_jefe: Optional[str] = None
    jefe_username: Optional[str] = None
    # Campos retrocompatibles
    id_supervisor: Optional[str] = None
    supervisor_username: Optional[str] = None
    subordinados_count: int = 0

    @model_validator(mode="before")
    @classmethod
    def populate_supervisor_alias(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if "id_jefe" in data and "id_supervisor" not in data:
                data["id_supervisor"] = data["id_jefe"]
            if "jefe_username" in data and "supervisor_username" not in data:
                data["supervisor_username"] = data["jefe_username"]
        return data

class JerarquiaResponse(BaseModel):
    # Nivel 1: Monitores con supervisores a su cargo
    monitores: List[HierarchicalUserItem] = []
    supervisores_sin_jefe: List[HierarchicalUserItem] = []
    supervisores_asignados: List[HierarchicalUserItem] = []

    # Nivel 2: Supervisores con cartógrafos a su cargo
    supervisores: List[HierarchicalUserItem] = []
    cartografos_sin_jefe: List[HierarchicalUserItem] = []
    cartografos_asignados: List[HierarchicalUserItem] = []

class AsignarJefeRequest(BaseModel):
    user_ids: List[str] = Field(..., min_length=1)
    id_jefe: Optional[str] = None # Si es None, desasigna

    @model_validator(mode="before")
    @classmethod
    def check_id_jefe_or_supervisor(cls, data: Any) -> Any:
        if isinstance(data, dict):
            if "id_jefe" not in data and "id_supervisor" in data:
                data["id_jefe"] = data["id_supervisor"]
        return data

# Para compatibilidad con importaciones existentes
AsignarSupervisorRequest = AsignarJefeRequest
