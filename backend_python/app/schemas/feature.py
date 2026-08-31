"""
Schemas Pydantic para Features cartográficas con soporte de auditoría y sincronización.
"""
from pydantic import BaseModel
from typing import Any, Dict, List, Optional
from datetime import datetime


class FeatureProperties(BaseModel):
    """Propiedades base para cualquier feature cartográfico."""
    # Campos de auditoría
    created_by: Optional[str] = None   # UUID del usuario que creó el registro
    updated_by: Optional[str] = None   # UUID del último usuario que modificó
    device_id:  Optional[str] = None   # Identificador del dispositivo móvil
    sync_version: int = 0              # Versión para resolución de conflictos

    class Config:
        extra = "allow"  # Permitir campos adicionales específicos de cada tabla


class EstructuraProperties(FeatureProperties):
    """Propiedades específicas para la capa de estructuras con referencias a catálogos."""
    id_categoria: int
    id_tipo: int
    id_estructura_user: Optional[int] = None
    nombre: Optional[str] = None
    notas: Optional[str] = None
    estado: Optional[str] = "presente"
    niveles_cantidad: int = 1


class NivelSyncItem(BaseModel):
    id: str
    estructura_id: str
    numero: int
    numero_locales: int = 1
    updated_at: Optional[str] = None
    deleted_at: Optional[str] = None
    sync_version: int = 0


class LocalSyncItem(BaseModel):
    id: str
    nivel_id: str
    nombre_local: Optional[str] = None
    id_tipo: int = 1
    id_condicion_local: Optional[int] = None
    numero_hogares: Optional[int] = None
    descripcion: Optional[str] = None
    updated_at: Optional[str] = None
    deleted_at: Optional[str] = None
    sync_version: int = 0


class HogarSyncItem(BaseModel):
    id: str
    local_id: str
    jefe_familia: Optional[str] = None
    id_sexo: Optional[int] = None
    id_idioma: Optional[int] = None
    direccion: Optional[str] = None
    total_habitantes: int = 0
    personas_0_5: int = 0
    personas_6_11: int = 0
    personas_12_17: int = 0
    personas_18_23: int = 0
    personas_24_34: int = 0
    personas_35_44: int = 0
    personas_45_59: int = 0
    personas_60_69: int = 0
    personas_70_79: int = 0
    personas_80_mas: int = 0
    personas_no_edad: int = 0
    updated_at: Optional[str] = None
    deleted_at: Optional[str] = None
    sync_version: int = 0


class SyncBatchItem(BaseModel):
    """Un ítem en el batch de sincronización offline."""
    id: Optional[str] = None
    geometry: Dict[str, Any]
    properties: Dict[str, Any] = {}


class SyncBatchPayload(BaseModel):
    """Payload completo del endpoint POST /api/sync."""
    puntos:   List[SyncBatchItem] = []
    lineas:   List[SyncBatchItem] = []
    poligonos: List[SyncBatchItem] = []
    niveles: List[NivelSyncItem] = []
    locales: List[LocalSyncItem] = []
    hogares: List[HogarSyncItem] = []
    # Metadatos de auditoría del dispositivo
    user_id:  Optional[str] = None   # UUID del usuario autenticado en el dispositivo
    device_id: Optional[str] = None  # Identificador único del dispositivo


class SyncedItem(BaseModel):
    """Resultado de sincronización de un ítem individual."""
    id: str
    sync_version: int
    updated_at: datetime


class SyncResult(BaseModel):
    """Respuesta completa del endpoint de sincronización."""
    status: str = "ok"
    synced: Dict[str, List[SyncedItem]] = {
        "puntos": [],
        "lineas": [],
        "poligonos": [],
        "niveles": [],
        "locales": [],
        "hogares": [],
    }

