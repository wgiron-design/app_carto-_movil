import asyncpg
import uuid
import json
from typing import Optional, Any, Dict

async def registrar_auditoria(
    pool: asyncpg.Pool,
    id_actor: Optional[str],
    accion: str,
    entidad: str,
    entidad_id: Optional[str] = None,
    detalle: Optional[Dict[str, Any]] = None
):
    """
    Registra una acción en la tabla audit_log para trazabilidad y seguridad.
    """
    try:
        actor_uuid = uuid.UUID(id_actor) if id_actor else None
        detalle_json = json.dumps(detalle, default=str) if detalle else None
        
        async with pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO audit_log (id_actor, accion, entidad, entidad_id, detalle)
                VALUES ($1, $2, $3, $4, $5::jsonb)
            """, actor_uuid, accion, entidad, entidad_id, detalle_json)
    except Exception as e:
        print(f"[AUDIT LOG ERROR] Falló al registrar auditoría: {e}")
