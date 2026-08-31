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
    Consolidado en la tabla asignacion_upms con rol_asignacion = 'supervisor'.
    """
    async with pool.acquire() as conn:
        supervisores_rows = await conn.fetch("""
            SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE LOWER(COALESCE(r.descripcion, '')) IN ('supervisor', 'gerente', 'admin', 'administrador') AND u.is_active = true
            ORDER BY u.username ASC
        """)
        supervisores = [
            {"id": str(r["id"]), "username": r["username"], "email": r["email"], "role": r["role"]}
            for r in supervisores_rows
        ]

        upms_disponibles_rows = await conn.fetch("""
            SELECT u.id, u.nombre, u.codigo_upm
            FROM upms u
            LEFT JOIN asignacion_upms au ON u.id = au.id_upm AND au.rol_asignacion = 'supervisor'
            WHERE au.id_upm IS NULL AND u.deleted_at IS NULL
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
                    SELECT 
                        u.id, 
                        u.nombre, 
                        u.codigo_upm, 
                        s.username as supervisor_username,
                        au.asignado_por,
                        ap.username as asignado_por_username,
                        au.asignado_en
                    FROM upms u
                    JOIN asignacion_upms au ON u.id = au.id_upm AND au.rol_asignacion = 'supervisor'
                    JOIN users s ON au.id_usuario = s.id
                    LEFT JOIN users ap ON au.asignado_por = ap.id
                    WHERE au.id_usuario = $1 AND u.deleted_at IS NULL
                    ORDER BY u.nombre ASC
                """, sup_uuid)
                upms_asignadas = [
                    UpmSimpleItem(
                        id=str(r["id"]),
                        nombre=r["nombre"] or "Sin nombre",
                        codigo_upm=r["codigo_upm"],
                        id_supervisor=supervisor_id,
                        supervisor_username=r["supervisor_username"],
                        asignado_por=str(r["asignado_por"]) if r["asignado_por"] else None,
                        asignado_por_username=r["asignado_por_username"],
                        asignado_en=r["asignado_en"]
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
    if not payload.id_supervisor or not payload.id_supervisor.strip():
        raise HTTPException(status_code=400, detail="Debe seleccionar un supervisor de destino.")
    if not payload.upm_ids or len(payload.upm_ids) == 0:
        raise HTTPException(status_code=400, detail="Debe seleccionar al menos una UPM para asignar.")

    try:
        sup_uuid = uuid.UUID(payload.id_supervisor)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="Uno o más identificadores UUID son inválidos.")

    async with pool.acquire() as conn:
        sup = await conn.fetchrow("SELECT username FROM users WHERE id = $1 AND is_active = true", sup_uuid)
        if not sup:
            raise HTTPException(status_code=404, detail="Supervisor no encontrado o inactivo.")

        actor_uuid = uuid.UUID(str(current_user["id"]))
        for u_id in upm_uuids:
            # Elimina cualquier asignación previa a otro supervisor para mantener 1 UPM -> 1 Supervisor
            await conn.execute("""
                DELETE FROM asignacion_upms 
                WHERE id_upm = $1 AND rol_asignacion = 'supervisor'
            """, u_id)

            # Inserta la nueva asignación
            await conn.execute("""
                INSERT INTO asignacion_upms (id_upm, id_usuario, rol_asignacion, asignado_por, asignado_en)
                VALUES ($1, $2, 'supervisor', $3, NOW())
            """, u_id, sup_uuid, actor_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_UPMS_SUPERVISOR",
        entidad="asignacion_upms",
        entidad_id=payload.id_supervisor,
        detalle={"upm_ids": payload.upm_ids, "supervisor": sup["username"], "rol_asignacion": "supervisor"}
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
    if not payload.upm_ids or len(payload.upm_ids) == 0:
        raise HTTPException(status_code=400, detail="Debe seleccionar al menos una UPM para desasignar.")

    try:
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="Uno o más UUIDs de UPM son inválidos.")

    async with pool.acquire() as conn:
        await conn.execute("""
            DELETE FROM asignacion_upms 
            WHERE rol_asignacion = 'supervisor' AND id_upm = ANY($1::uuid[])
        """, upm_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="DESASIGNAR_UPMS_SUPERVISOR",
        entidad="asignacion_upms",
        detalle={"upm_ids": payload.upm_ids, "rol_asignacion": "supervisor"}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs liberadas exitosamente."}


# -------------------------------------------------------------
# 2. Asignación UPMs -> Cartógrafo (1 a N: 1 UPM -> N Cartógrafos)
# -------------------------------------------------------------

@router.get("/api/v1/upms/cartografos", response_model=AsignacionUpmCartografoResponse)
async def get_upms_for_cartografos(
    supervisor_id: Optional[str] = Query(None),
    cartografo_id: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Jerarquía operativa: Supervisor -> Cartógrafos asignados -> UPMs del Supervisor.
    1. Combo Supervisor:
       - Administradores / Gerentes / Monitores: Ven supervisores disponibles.
       - Supervisores: Ven su propio perfil preseleccionado.
    2. Combo Cartógrafos:
       - Cartógrafos asignados directamente al supervisor seleccionado (u.id_jefe = supervisor_id).
    3. UPMs Disponibles (Lista izquierda):
       - UPMs que tiene asignado el supervisor y que no han sido asignados a ningún cartógrafo.
    4. UPMs Asignadas (Lista derecha):
       - UPMs asignadas al cartógrafo seleccionado.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role not in ("supervisor", "monitor"):
        raise HTTPException(status_code=403, detail="Acceso denegado. Se requiere rol administrador, monitor o supervisor.")

    user_uuid = uuid.UUID(str(current_user["id"]))

    async with pool.acquire() as conn:
        # 1. Lista de Supervisores
        if is_admin(user_role):
            sup_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                WHERE LOWER(COALESCE(r.descripcion, '')) IN ('supervisor', 'administrador', 'admin', 'gerente') 
                  AND u.is_active = true
                ORDER BY u.username ASC
            """)
        elif user_role == "monitor":
            sup_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                WHERE (u.id_jefe = $1 OR u.id = $1)
                  AND LOWER(COALESCE(r.descripcion, '')) IN ('supervisor', 'monitor')
                  AND u.is_active = true
                ORDER BY u.username ASC
            """, user_uuid)
            if not sup_rows:
                sup_rows = await conn.fetch("""
                    SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
                    FROM users u
                    LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                    WHERE LOWER(COALESCE(r.descripcion, '')) = 'supervisor' AND u.is_active = true
                    ORDER BY u.username ASC
                """)
        else: # supervisor
            sup_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, COALESCE(r.descripcion, 'supervisor') as role
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                WHERE u.id = $1 AND u.is_active = true
            """, user_uuid)

        supervisores = [
            {"id": str(r["id"]), "username": r["username"], "email": r["email"], "role": r["role"]}
            for r in sup_rows
        ]

        # Determinar Supervisor Seleccionado
        selected_sup_uuid: Optional[uuid.UUID] = None
        if user_role == "supervisor":
            selected_sup_uuid = user_uuid
        elif supervisor_id:
            try:
                selected_sup_uuid = uuid.UUID(supervisor_id)
            except ValueError:
                selected_sup_uuid = None

        if not selected_sup_uuid and supervisores:
            selected_sup_uuid = uuid.UUID(supervisores[0]["id"])

        selected_supervisor_id = str(selected_sup_uuid) if selected_sup_uuid else None

        # 2. Cartógrafos asignados a dicho Supervisor
        cartografos = []
        if selected_sup_uuid:
            cart_rows = await conn.fetch("""
                SELECT u.id, u.username, u.email, sup.username as supervisor_username
                FROM users u
                LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
                LEFT JOIN users sup ON u.id_jefe = sup.id
                WHERE LOWER(COALESCE(r.descripcion, '')) IN ('cartografo', 'monitor', 'consulta') 
                  AND u.id_jefe = $1 
                  AND u.is_active = true
                ORDER BY u.username ASC
            """, selected_sup_uuid)

            cartografos = [
                {"id": str(r["id"]), "username": r["username"], "email": r["email"], "supervisor_username": r["supervisor_username"]}
                for r in cart_rows
            ]

        # Determinar Cartógrafo Seleccionado
        selected_cart_uuid: Optional[uuid.UUID] = None
        if cartografo_id:
            try:
                cand_uuid = uuid.UUID(cartografo_id)
                if any(c["id"] == str(cand_uuid) for c in cartografos):
                    selected_cart_uuid = cand_uuid
            except ValueError:
                selected_cart_uuid = None

        if not selected_cart_uuid and cartografos:
            selected_cart_uuid = uuid.UUID(cartografos[0]["id"])

        selected_cartografo_id = str(selected_cart_uuid) if selected_cart_uuid else None

        # 3. UPMs que tiene asignado el Supervisor y que NO han sido asignadas a ningún cartógrafo
        upms_disponibles = []
        if selected_sup_uuid:
            upms_disp_rows = await conn.fetch("""
                SELECT u.id, u.nombre, u.codigo_upm, 0 as cartografos_count
                FROM upms u
                JOIN asignacion_upms aus ON u.id = aus.id_upm AND aus.rol_asignacion = 'supervisor' AND aus.id_usuario = $1
                WHERE u.deleted_at IS NULL
                  AND NOT EXISTS (
                      SELECT 1 FROM asignacion_upms auc 
                      WHERE auc.id_upm = u.id AND auc.rol_asignacion = 'cartografo'
                  )
                ORDER BY u.nombre ASC
            """, selected_sup_uuid)

            upms_disponibles = [
                UpmSimpleItem(
                    id=str(r["id"]),
                    nombre=r["nombre"] or "Sin nombre",
                    codigo_upm=r["codigo_upm"],
                    cartografos_count=r["cartografos_count"]
                )
                for r in upms_disp_rows
            ]

        # 4. UPMs asignadas al cartógrafo seleccionado
        upms_asignadas = []
        if selected_cart_uuid:
            upms_asig_rows = await conn.fetch("""
                SELECT 
                    u.id, 
                    u.nombre, 
                    u.codigo_upm,
                    auc.asignado_por,
                    ap.username as asignado_por_username,
                    auc.asignado_en
                FROM upms u
                JOIN asignacion_upms auc ON u.id = auc.id_upm AND auc.rol_asignacion = 'cartografo'
                LEFT JOIN users ap ON auc.asignado_por = ap.id
                WHERE auc.id_usuario = $1 AND u.deleted_at IS NULL
                ORDER BY u.nombre ASC
            """, selected_cart_uuid)

            upms_asignadas = [
                UpmSimpleItem(
                    id=str(r["id"]),
                    nombre=r["nombre"] or "Sin nombre",
                    codigo_upm=r["codigo_upm"],
                    asignado_por=str(r["asignado_por"]) if r["asignado_por"] else None,
                    asignado_por_username=r["asignado_por_username"],
                    asignado_en=r["asignado_en"]
                )
                for r in upms_asig_rows
            ]

    return AsignacionUpmCartografoResponse(
        supervisores=supervisores,
        selected_supervisor_id=selected_supervisor_id,
        cartografos=cartografos,
        selected_cartografo_id=selected_cartografo_id,
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
    Asigna UPMs a un cartógrafo en asignacion_upms.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role not in ("supervisor", "monitor"):
        raise HTTPException(status_code=403, detail="Acceso denegado.")

    if not payload.id_cartografo or not payload.id_cartografo.strip():
        raise HTTPException(status_code=400, detail="Debe seleccionar un cartógrafo de destino.")
    if not payload.upm_ids or len(payload.upm_ids) == 0:
        raise HTTPException(status_code=400, detail="Debe seleccionar al menos una UPM para asignar.")

    try:
        cart_uuid = uuid.UUID(payload.id_cartografo)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="Uno o más identificadores UUID son inválidos.")

    async with pool.acquire() as conn:
        cart = await conn.fetchrow("SELECT username, id_jefe FROM users WHERE id = $1 AND is_active = true", cart_uuid)
        if not cart:
            raise HTTPException(status_code=404, detail="Cartógrafo no encontrado o inactivo.")

        if user_role == "supervisor":
            # Si el cartógrafo tiene otro supervisor asignado, rechazar
            if cart["id_jefe"] is not None and str(cart["id_jefe"]) != str(current_user["id"]):
                raise HTTPException(status_code=403, detail="No tienes permisos para asignar tareas a este cartógrafo.")

            # Verificar que las UPMs pertenezcan a este supervisor en asignacion_upms
            sup_upms = await conn.fetch("""
                SELECT id_upm FROM asignacion_upms 
                WHERE rol_asignacion = 'supervisor' AND id_usuario = $1 AND id_upm = ANY($2::uuid[])
            """, uuid.UUID(str(current_user["id"])), upm_uuids)
            if len(sup_upms) != len(upm_uuids):
                raise HTTPException(status_code=403, detail="Una o más UPMs seleccionadas no están bajo su supervisión.")

        actor_uuid = uuid.UUID(str(current_user["id"]))
        for u_id in upm_uuids:
            # Elimina asignación previa a cualquier otro cartógrafo para garantizar que pertenezca al cartógrafo seleccionado
            await conn.execute("""
                DELETE FROM asignacion_upms
                WHERE id_upm = $1 AND rol_asignacion = 'cartografo'
            """, u_id)

            await conn.execute("""
                INSERT INTO asignacion_upms (id_upm, id_usuario, rol_asignacion, asignado_por, asignado_en)
                VALUES ($1, $2, 'cartografo', $3, NOW())
            """, u_id, cart_uuid, actor_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ASIGNAR_UPMS_CARTOGRAFO",
        entidad="asignacion_upms",
        entidad_id=payload.id_cartografo,
        detalle={"upm_ids": payload.upm_ids, "cartografo": cart["username"], "rol_asignacion": "cartografo"}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs asignadas al cartógrafo correctamente."}

@router.post("/api/v1/upms/desasignar-cartografo")
async def unassign_upms_from_cartografo(
    payload: DesasignarUpmCartografoRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Remueve la asignación de UPMs a un cartógrafo en asignacion_upms.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    if not is_admin(user_role) and user_role not in ("supervisor", "monitor"):
        raise HTTPException(status_code=403, detail="Acceso denegado.")

    if not payload.id_cartografo or not payload.id_cartografo.strip():
        raise HTTPException(status_code=400, detail="Debe indicar el cartógrafo a desasignar.")
    if not payload.upm_ids or len(payload.upm_ids) == 0:
        raise HTTPException(status_code=400, detail="Debe seleccionar al menos una UPM para desasignar.")

    try:
        cart_uuid = uuid.UUID(payload.id_cartografo)
        upm_uuids = [uuid.UUID(uid) for uid in payload.upm_ids]
    except ValueError:
        raise HTTPException(status_code=400, detail="UUIDs inválidos.")

    async with pool.acquire() as conn:
        await conn.execute("""
            DELETE FROM asignacion_upms
            WHERE rol_asignacion = 'cartografo' AND id_usuario = $1 AND id_upm = ANY($2::uuid[])
        """, cart_uuid, upm_uuids)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="DESASIGNAR_UPMS_CARTOGRAFO",
        entidad="asignacion_upms",
        entidad_id=payload.id_cartografo,
        detalle={"upm_ids": payload.upm_ids, "rol_asignacion": "cartografo"}
    )

    return {"success": True, "message": f"{len(upm_uuids)} UPMs desasignadas del cartógrafo."}
