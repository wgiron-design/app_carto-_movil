from fastapi import APIRouter, HTTPException, status, Depends, Query
import asyncpg
from typing import Dict, Any, List, Optional
import uuid

from app.database import get_db_pool
from app.security import require_role, get_current_active_user
from app.core.constants import is_admin, normalize_role
from app.schemas.upms import (
    AsignacionUpmSupervisorResponse,
    AsignarUpmSupervisorRequest,
    DesasignarUpmSupervisorRequest,
    AsignacionUpmCartografoResponse,
    AsignarUpmCartografoRequest,
    DesasignarUpmCartografoRequest,
    UpmSimpleItem
)
from app.services.auditoria import registrar_auditoria

router = APIRouter(tags=["UPMs y Asignaciones"])

# -------------------------------------------------------------
# 1. Asignación UPMs -> Supervisor (1 a 1: 1 UPM -> 1 Supervisor)
# -------------------------------------------------------------

@router.get("/api/v1/admin/upms/supervisores", response_model=AsignacionUpmSupervisorResponse)
async def get_upms_for_supervisores(
    supervisor_id: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Lista los supervisores disponibles, las UPMs sin asignar a ningún supervisor,
    y las UPMs asignadas al supervisor seleccionado.
    """
    async with pool.acquire() as conn:
        supervisores_rows = await conn.fetch("""
            SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE LOWER(r.descripcion) IN ('supervisor', 'admin', 'administrador') AND u.is_active = true
            ORDER BY u.username ASC
        """)
        supervisores = [
            {"id": str(r["id"]), "username": r["username"], "email": r["email"], "role": r["role"]}
            for r in supervisores_rows
        ]

        upms_disponibles_rows = await conn.fetch("""
            SELECT u.id, u.nombre, u.codigo_upm
            FROM upms u
            LEFT JOIN asignacion_upms_supervisor aus ON u.id = aus.id_upm
            WHERE aus.id_upm IS NULL
            ORDER BY u.nombre ASC
        """)
        upms_disponibles = [
            UpmSimpleItem(id=str(r["id"]), nombre=r["nombre"] or "Sin nombre", codigo_upm=r["codigo_upm"])
            for r in upms_disponibles_rows
        ]

        upms_asignadas = []
        if supervisor_id:
            try:
                sup_uuid = uuid.UUID(supervisor_id)
                upms_asig_rows = await conn.fetch("""
                    SELECT u.id, u.nombre, u.codigo_upm, s.username as supervisor_username
                    FROM upms u
                    JOIN asignacion_upms_supervisor aus ON u.id = aus.id_upm
                    JOIN users s ON aus.id_supervisor = s.id
                    WHERE aus.id_supervisor = $1
                    ORDER BY u.nombre ASC
                """, sup_uuid)
                upms_asignadas = [
                    UpmSimpleItem(
                        id=str(r["id"]),
                        nombre=r["nombre"] or "Sin nombre",
                        codigo_upm=r["codigo_upm"],
                        id_supervisor=supervisor_id,
                        supervisor_username=r["supervisor_username"]
                    )
                    for r in upms_asig_rows
                ]
            except ValueError:
                raise HTTPException(status_code=400, detail="ID de supervisor inválido.")

    return AsignacionUpmSupervisorResponse(
        supervisores=supervisores,
        upms_disponibles=upms_disponibles,
        upms_asignadas=upms_asignadas
    )

@router.post("/api/v1/admin/upms/asignar-supervisor")
async def assign_upms_to_supervisor(
    payload: AsignarUpmSupervisorRequest,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Asigna una lista de UPMs a un supervisor.
    Regla: Cada UPM solo puede pertenecer a 1 único supervisor.
    """
    try:
        sup_uuid = uuid.UUID(payload.id_supervisor)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="Uno o más identificadores UUID son inválidos.")

    async with pool.acquire() as conn:
        sup = await conn.fetchrow("SELECT username FROM users WHERE id = $1 AND is_active = true", sup_uuid)
        if not sup:
            raise HTTPException(status_code=404, detail="Supervisor no encontrado o inactivo.")

        conflict = await conn.fetch("""
            SELECT u.nombre, aus.id_supervisor, s.username as current_supervisor
            FROM asignacion_upms_supervisor aus
            JOIN upms u ON aus.id_upm = u.id
            JOIN users s ON aus.id_supervisor = s.id
            WHERE aus.id_upm = ANY($1::uuid[]) AND aus.id_supervisor != $2
        """, upm_uuids, sup_uuid)

        if conflict:
            nombres = ", ".join([f"'{c['nombre']}' (asignada a {c['current_supervisor']})" for c in conflict])
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Las siguientes UPMs ya están asignadas a otro supervisor: {nombres}"
            )

        for u_id in upm_uuids:
            await conn.execute("""
                INSERT INTO asignacion_upms_supervisor (id_upm, id_supervisor, asignado_por)
                VALUES ($1, $2, $3)
                ON CONFLICT (id_upm) DO UPDATE SET id_supervisor = $2, asignado_por = $3, asignado_en = NOW()
            """, u_id, sup_uuid, uuid.UUID(str(current_user["id"])))

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_UPMS_SUPERVISOR",
        entidad="asignacion_upms_supervisor",
        entidad_id=payload.id_supervisor,
        detalle={"upm_ids": payload.upm_ids, "supervisor": sup["username"]}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs asignadas al supervisor exitosamente."}

@router.post("/api/v1/admin/upms/desasignar-supervisor")
async def unassign_upms_from_supervisor(
    payload: DesasignarUpmSupervisorRequest,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Desasigna una lista de UPMs de sus supervisores actuales.
    """
    try:
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="Uno o más UUIDs de UPM son inválidos.")

    async with pool.acquire() as conn:
        await conn.execute("""
            DELETE FROM asignacion_upms_supervisor 
            WHERE id_upm = ANY($1::uuid[])
        """, upm_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="DESASIGNAR_UPMS_SUPERVISOR",
        entidad="asignacion_upms_supervisor",
        detalle={"upm_ids": payload.upm_ids}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs liberadas exitosamente."}


# -------------------------------------------------------------
# 2. Asignación UPMs -> Cartógrafo (1 a N: 1 UPM -> N Cartógrafos)
# -------------------------------------------------------------

@router.get("/api/v1/upms/cartografos", response_model=AsignacionUpmCartografoResponse)
async def get_upms_for_cartografos(
    cartografo_id: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Lista cartógrafos disponibles y las UPMs asociadas.
    - Administrador: ve todos los cartógrafos y todas las UPMs.
    - Supervisor: ve solo los cartógrafos bajo su supervisión directa y las UPMs asignadas a él.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role != "supervisor":
        raise HTTPException(status_code=403, detail="Acceso denegado. Se requiere rol administrador o supervisor.")

    user_uuid = uuid.UUID(str(current_user["id"]))

    async with pool.acquire() as conn:
        if is_admin(user_role):
            cart_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, sup.username as supervisor_username
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                LEFT JOIN users sup ON u.id_supervisor = sup.id
                WHERE LOWER(r.descripcion) IN ('cartografo', 'consulta') AND u.is_active = true
                ORDER BY u.username ASC
            """)
        else: # supervisor
            cart_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, sup.username as supervisor_username
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                LEFT JOIN users sup ON u.id_supervisor = sup.id
                WHERE LOWER(r.descripcion) IN ('cartografo', 'consulta') AND u.id_supervisor = $1 AND u.is_active = true
                ORDER BY u.username ASC
            """, user_uuid)

        cartografos = [
            {"id": str(r["id"]), "username": r["username"], "email": r["email"], "supervisor_username": r["supervisor_username"]}
            for r in cart_rows
        ]

        if is_admin(user_role):
            upms_disp_rows = await conn.fetch("""
                SELECT u.id, u.nombre, u.codigo_upm, COUNT(auc.id_cartografo)::int as cartografos_count
                FROM upms u
                LEFT JOIN asignacion_upms_cartografo auc ON u.id = auc.id_upm
                GROUP BY u.id, u.nombre, u.codigo_upm
                ORDER BY u.nombre ASC
            """)
        else: # supervisor
            upms_disp_rows = await conn.fetch("""
                SELECT u.id, u.nombre, u.codigo_upm, COUNT(auc.id_cartografo)::int as cartografos_count
                FROM upms u
                JOIN asignacion_upms_supervisor aus ON u.id = aus.id_upm AND aus.id_supervisor = $1
                LEFT JOIN asignacion_upms_cartografo auc ON u.id = auc.id_upm
                GROUP BY u.id, u.nombre, u.codigo_upm
                ORDER BY u.nombre ASC
            """, user_uuid)

        upms_disponibles = [
            UpmSimpleItem(
                id=str(r["id"]),
                nombre=r["nombre"] or "Sin nombre",
                codigo_upm=r["codigo_upm"],
                cartografos_count=r["cartografos_count"]
            )
            for r in upms_disp_rows
        ]

        upms_asignadas = []
        if cartografo_id:
            try:
                cart_uuid = uuid.UUID(cartografo_id)
                upms_asig_rows = await conn.fetch("""
                    SELECT u.id, u.nombre, u.codigo_upm
                    FROM upms u
                    JOIN asignacion_upms_cartografo auc ON u.id = auc.id_upm
                    WHERE auc.id_cartografo = $1
                    ORDER BY u.nombre ASC
                """, cart_uuid)
                upms_asignadas = [
                    UpmSimpleItem(id=str(r["id"]), nombre=r["nombre"] or "Sin nombre", codigo_upm=r["codigo_upm"])
                    for r in upms_asig_rows
                ]
            except ValueError:
                raise HTTPException(status_code=400, detail="ID de cartógrafo inválido.")

    return AsignacionUpmCartografoResponse(
        cartografos=cartografos,
        upms_disponibles=upms_disponibles,
        upms_asignadas=upms_asignadas
    )

@router.post("/api/v1/upms/asignar-cartografo")
async def assign_upms_to_cartografo(
    payload: AsignarUpmCartografoRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Asigna UPMs a un cartógrafo (1 UPM -> N Cartógrafos).
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role != "supervisor":
        raise HTTPException(status_code=403, detail="Acceso denegado.")

    try:
        cart_uuid = uuid.UUID(payload.id_cartografo)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="UUIDs inválidos.")

    async with pool.acquire() as conn:
        cart = await conn.fetchrow("SELECT username, id_supervisor FROM users WHERE id = $1 AND is_active = true", cart_uuid)
        if not cart:
            raise HTTPException(status_code=404, detail="Cartógrafo no encontrado.")

        if user_role == "supervisor":
            if str(cart["id_supervisor"]) != str(current_user["id"]):
                raise HTTPException(status_code=403, detail="No tienes permisos para asignar tareas a este cartógrafo.")

        for u_id in upm_uuids:
            await conn.execute("""
                INSERT INTO asignacion_upms_cartografo (id_upm, id_cartografo, asignado_por)
                VALUES ($1, $2, $3)
                ON CONFLICT (id_upm, id_cartografo) DO NOTHING
            """, u_id, cart_uuid, uuid.UUID(str(current_user["id"])))

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_UPMS_CARTOGRAFO",
        entidad="asignacion_upms_cartografo",
        entidad_id=payload.id_cartografo,
        detalle={"upm_ids": payload.upm_ids, "cartografo": cart["username"]}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs asignadas al cartógrafo correctamente."}

@router.post("/api/v1/upms/desasignar-cartografo")
async def unassign_upms_from_cartografo(
    payload: DesasignarUpmCartografoRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Remueve la asignación de UPMs a un cartógrafo.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role != "supervisor":
        raise HTTPException(status_code=403, detail="Acceso denegado.")

    try:
        cart_uuid = uuid.UUID(payload.id_cartografo)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="UUIDs inválidos.")

    async with pool.acquire() as conn:
        await conn.execute("""
            DELETE FROM asignacion_upms_cartografo
            WHERE id_cartografo = $1 AND id_upm = ANY($2::uuid[])
        """, cart_uuid, upm_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="DESASIGNAR_UPMS_CARTOGRAFO",
        entidad="asignacion_upms_cartografo",
        entidad_id=payload.id_cartografo,
        detalle={"upm_ids": payload.upm_ids}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs desasignadas del cartógrafo."}
