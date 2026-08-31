from fastapi import APIRouter, HTTPException, status, Depends
import asyncpg
from typing import Dict, Any, List
import uuid

from app.database import get_db_pool
from app.security import require_role
from app.schemas.jerarquia import JerarquiaResponse, HierarchicalUserItem, AsignarJefeRequest
from app.services.auditoria import registrar_auditoria

router = APIRouter(prefix="/api/v1/admin/jerarquia", tags=["Admin - Jerarquía"])

@router.get("", response_model=JerarquiaResponse)
async def get_jerarquia(
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Obtiene el panorama jerárquico multinivel utilizando cat_roles e id_jefe:
    Nivel 1: Monitores tienen a cargo Supervisores.
    Nivel 2: Supervisores tienen a cargo Cartógrafos.
    """
    async with pool.acquire() as conn:
        # 1. Monitores (Jefes de nivel 1: tienen a cargo supervisores)
        monitores_rows = await conn.fetch("""
            SELECT 
                m.id, 
                m.username, 
                m.email, 
                COALESCE(r.descripcion, 'monitor') as role, 
                m.id_jefe, 
                jefe.username as jefe_username,
                COUNT(sub.id)::int as subordinados_count
            FROM users m
            LEFT JOIN cat_roles r ON m.id_cat_rol = r.id
            LEFT JOIN users jefe ON m.id_jefe = jefe.id
            LEFT JOIN users sub ON sub.id_jefe = m.id AND sub.is_active = true
            WHERE LOWER(r.descripcion) = 'monitor' AND m.is_active = true
            GROUP BY m.id, m.username, m.email, r.descripcion, m.id_jefe, jefe.username
            ORDER BY m.username ASC
        """)

        # 2. Supervisores (Subordinados de monitores, y jefes de cartógrafos)
        supervisores_rows = await conn.fetch("""
            SELECT 
                s.id, 
                s.username, 
                s.email, 
                COALESCE(r.descripcion, 'supervisor') as role, 
                s.id_jefe, 
                jefe.username as jefe_username,
                COUNT(sub.id)::int as subordinados_count
            FROM users s
            LEFT JOIN cat_roles r ON s.id_cat_rol = r.id
            LEFT JOIN users jefe ON s.id_jefe = jefe.id
            LEFT JOIN users sub ON sub.id_jefe = s.id AND sub.is_active = true
            WHERE LOWER(r.descripcion) IN ('supervisor', 'gerente') AND s.is_active = true
            GROUP BY s.id, s.username, s.email, r.descripcion, s.id_jefe, jefe.username
            ORDER BY s.username ASC
        """)

        # 3. Cartógrafos (Subordinados de supervisores)
        cartografos_rows = await conn.fetch("""
            SELECT 
                c.id, 
                c.username, 
                c.email, 
                COALESCE(r.descripcion, 'cartografo') as role, 
                c.id_jefe, 
                jefe.username as jefe_username,
                0 as subordinados_count
            FROM users c
            LEFT JOIN cat_roles r ON c.id_cat_rol = r.id
            LEFT JOIN users jefe ON c.id_jefe = jefe.id
            WHERE LOWER(r.descripcion) IN ('cartografo', 'consulta') AND c.is_active = true
            ORDER BY c.username ASC
        """)

    monitores = [
        HierarchicalUserItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_jefe=str(r["id_jefe"]) if r["id_jefe"] else None,
            jefe_username=r["jefe_username"],
            subordinados_count=r["subordinados_count"]
        )
        for r in monitores_rows
    ]

    supervisores_sin_jefe = []
    supervisores_asignados = []
    supervisores = []

    for r in supervisores_rows:
        item = HierarchicalUserItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_jefe=str(r["id_jefe"]) if r["id_jefe"] else None,
            jefe_username=r["jefe_username"],
            subordinados_count=r["subordinados_count"]
        )
        supervisores.append(item)
        if r["id_jefe"]:
            supervisores_asignados.append(item)
        else:
            supervisores_sin_jefe.append(item)

    cartografos_sin_jefe = []
    cartografos_asignados = []

    for r in cartografos_rows:
        item = HierarchicalUserItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_jefe=str(r["id_jefe"]) if r["id_jefe"] else None,
            jefe_username=r["jefe_username"],
            subordinados_count=0
        )
        if r["id_jefe"]:
            cartografos_asignados.append(item)
        else:
            cartografos_sin_jefe.append(item)

    return JerarquiaResponse(
        monitores=monitores,
        supervisores_sin_jefe=supervisores_sin_jefe,
        supervisores_asignados=supervisores_asignados,
        supervisores=supervisores,
        cartografos_sin_jefe=cartografos_sin_jefe,
        cartografos_asignados=cartografos_asignados
    )

@router.post("/asignar-jefe")
@router.post("/asignar-supervisor")
async def assign_jefe(
    payload: AsignarJefeRequest,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Asigna o desasigna un jefe inmediato a una lista de usuarios.
    Previene ciclos jerárquicos y auto-asignaciones.
    """
    jefe_uuid = None
    if payload.id_jefe:
        try:
            jefe_uuid = uuid.UUID(payload.id_jefe)
        except ValueError:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ID de jefe inválido.")

    try:
        user_uuids = [uuid.UUID(uid) for uid in payload.user_ids]
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uno o más IDs de usuario son inválidos.")

    if jefe_uuid and jefe_uuid in user_uuids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Un usuario no puede ser su propio jefe.")

    async with pool.acquire() as conn:
        if jefe_uuid:
            jefe_row = await conn.fetchrow("SELECT username FROM users WHERE id = $1 AND is_active = true", jefe_uuid)
            if not jefe_row:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="El jefe especificado no existe o está inactivo.")

        await conn.execute("""
            UPDATE users 
            SET id_jefe = $1, updated_at = NOW() 
            WHERE id = ANY($2::uuid[])
        """, jefe_uuid, user_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_JEFE" if jefe_uuid else "DESASIGNAR_JEFE",
        entidad="users_hierarchy",
        entidad_id=str(jefe_uuid) if jefe_uuid else None,
        detalle={"user_ids": payload.user_ids, "id_jefe": payload.id_jefe}
    )

    return {
        "success": True,
        "message": f"Se actualizaron {len(user_uuids)} asignaciones jerárquicas correctamente."
    }
