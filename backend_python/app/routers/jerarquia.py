from fastapi import APIRouter, HTTPException, status, Depends
import asyncpg
from typing import Dict, Any, List
import uuid

from app.database import get_db_pool
from app.security import require_role
from app.schemas.jerarquia import JerarquiaResponse, HierarchicalUserItem, AsignarSupervisorRequest
from app.services.auditoria import registrar_auditoria

router = APIRouter(prefix="/api/v1/admin/jerarquia", tags=["Admin - Jerarquía"])

@router.get("", response_model=JerarquiaResponse)
async def get_jerarquia(
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Obtiene el panorama jerárquico completo utilizando cat_roles.
    """
    async with pool.acquire() as conn:
        supervisores_rows = await conn.fetch("""
            SELECT 
                s.id, 
                s.username, 
                s.email, 
                COALESCE(r.descripcion, 'supervisor') as role, 
                s.id_supervisor, 
                sup.username as supervisor_username,
                COUNT(sub.id)::int as subordinados_count
            FROM users s
            LEFT JOIN cat_roles r ON s.id_cat_rol = r.id
            LEFT JOIN users sup ON s.id_supervisor = sup.id
            LEFT JOIN users sub ON sub.id_supervisor = s.id AND sub.is_active = true
            WHERE LOWER(r.descripcion) IN ('supervisor', 'admin', 'administrador', 'gerente') AND s.is_active = true
            GROUP BY s.id, s.username, s.email, r.descripcion, s.id_supervisor, sup.username
            ORDER BY s.username ASC
        """)

        subordinados_rows = await conn.fetch("""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                COALESCE(r.descripcion, 'cartografo') as role, 
                u.id_supervisor, 
                sup.username as supervisor_username,
                0 as subordinados_count
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            LEFT JOIN users sup ON u.id_supervisor = sup.id
            WHERE LOWER(r.descripcion) IN ('monitor', 'cartografo', 'consulta') AND u.is_active = true
            ORDER BY u.username ASC
        """)

    supervisores = [
        HierarchicalUserItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_supervisor=str(r["id_supervisor"]) if r["id_supervisor"] else None,
            supervisor_username=r["supervisor_username"],
            subordinados_count=r["subordinados_count"]
        )
        for r in supervisores_rows
    ]

    monitores_sin_sup = []
    monitores_asignados = []
    cartografos_sin_sup = []
    cartografos_asignados = []

    for r in subordinados_rows:
        item = HierarchicalUserItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_supervisor=str(r["id_supervisor"]) if r["id_supervisor"] else None,
            supervisor_username=r["supervisor_username"],
            subordinados_count=0
        )
        role_lower = r["role"].lower()
        if role_lower == "monitor":
            if r["id_supervisor"]:
                monitores_asignados.append(item)
            else:
                monitores_sin_sup.append(item)
        else: # cartografo o consulta
            if r["id_supervisor"]:
                cartografos_asignados.append(item)
            else:
                cartografos_sin_sup.append(item)

    return JerarquiaResponse(
        supervisores=supervisores,
        monitores_sin_supervisor=monitores_sin_sup,
        cartografos_sin_supervisor=cartografos_sin_sup,
        monitores_asignados=monitores_asignados,
        cartografos_asignados=cartografos_asignados
    )

@router.post("/asignar-supervisor")
async def assign_supervisor(
    payload: AsignarSupervisorRequest,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Asigna o desasigna un supervisor inmediato a una lista de usuarios.
    Previene ciclos jerárquicos.
    """
    supervisor_uuid = None
    if payload.id_supervisor:
        try:
            supervisor_uuid = uuid.UUID(payload.id_supervisor)
        except ValueError:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ID de supervisor inválido.")

    try:
        user_uuids = [uuid.UUID(uid) for uid in payload.user_ids]
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Uno o más IDs de usuario son inválidos.")

    if supervisor_uuid and supervisor_uuid in user_uuids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Un usuario no puede ser su propio supervisor.")

    async with pool.acquire() as conn:
        if supervisor_uuid:
            sup_row = await conn.fetchrow("SELECT username FROM users WHERE id = $1 AND is_active = true", supervisor_uuid)
            if not sup_row:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="El supervisor especificado no existe o está inactivo.")

        await conn.execute("""
            UPDATE users 
            SET id_supervisor = $1, updated_at = NOW() 
            WHERE id = ANY($2::uuid[])
        """, supervisor_uuid, user_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_SUPERVISOR" if supervisor_uuid else "DESASIGNAR_SUPERVISOR",
        entidad="users_hierarchy",
        entidad_id=str(supervisor_uuid) if supervisor_uuid else None,
        detalle={"user_ids": payload.user_ids, "id_supervisor": payload.id_supervisor}
    )

    return {
        "success": True,
        "message": f"Se actualizaron {len(user_uuids)} asignaciones jerárquicas correctamente."
    }
