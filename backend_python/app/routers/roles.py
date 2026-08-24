from fastapi import APIRouter, HTTPException, status, Depends
import asyncpg
from typing import List, Dict, Any
import uuid

from app.database import get_db_pool
from app.security import require_role
from app.core.constants import ADMIN_ROLES, is_admin
from app.schemas.roles import RoleConfigResponse, RoleUpdateConfig
from app.services.auditoria import registrar_auditoria

router = APIRouter(prefix="/api/v1/admin/roles", tags=["Admin - Roles"])

@router.get("", response_model=List[RoleConfigResponse])
async def list_roles(
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Retorna la lista de roles desde la tabla cat_roles con el conteo de usuarios activos.
    """
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT 
                r.id, 
                r.descripcion, 
                r.activo, 
                r.updated_at,
                COUNT(u.id)::int as total_usuarios
            FROM cat_roles r
            LEFT JOIN users u ON u.id_cat_rol = r.id AND u.is_active = true
            GROUP BY r.id, r.descripcion, r.activo, r.updated_at
            ORDER BY r.descripcion ASC
        """)

        return [
            RoleConfigResponse(
                id=str(r["id"]),
                descripcion=r["descripcion"],
                activo=r["activo"],
                total_usuarios=r["total_usuarios"],
                updated_at=r["updated_at"]
            )
            for r in rows
        ]

@router.patch("/{role_id_or_name}", response_model=RoleConfigResponse)
async def update_role_config(
    role_id_or_name: str,
    payload: RoleUpdateConfig,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Actualiza la descripción o estado activo/inactivo de un rol en cat_roles.
    REGLA DURA: El rol 'admin' jamás puede ser desactivado (HTTP 409).
    """
    async with pool.acquire() as conn:
        # Buscar rol por UUID o por descripción
        role_uuid = None
        try:
            role_uuid = uuid.UUID(role_id_or_name)
            existing = await conn.fetchrow("SELECT id, descripcion, activo FROM cat_roles WHERE id = $1", role_uuid)
        except ValueError:
            existing = await conn.fetchrow("SELECT id, descripcion, activo FROM cat_roles WHERE LOWER(descripcion) = LOWER($1)", role_id_or_name)

        if not existing:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Rol '{role_id_or_name}' no encontrado en cat_roles.")

        # Validar regla dura de admin
        if is_admin(existing["descripcion"]) and payload.activo is False:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El rol administrador es vital para el sistema y no puede ser desactivado."
            )

        updates = []
        args = []
        idx = 1

        if payload.descripcion is not None:
            new_desc = payload.descripcion.strip().lower()
            if is_admin(existing["descripcion"]) and not is_admin(new_desc):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="No se puede renombrar el rol administrador a otro valor."
                )
            updates.append(f"descripcion = ${idx}")
            args.append(new_desc)
            idx += 1

        if payload.activo is not None:
            updates.append(f"activo = ${idx}")
            args.append(payload.activo)
            idx += 1

        if not updates:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No se proporcionaron datos para actualizar.")

        updates.append("updated_at = NOW()")
        args.append(existing["id"])

        sql = f"""
            UPDATE cat_roles
            SET {', '.join(updates)}
            WHERE id = ${idx}
            RETURNING id, descripcion, activo, updated_at
        """
        row = await conn.fetchrow(sql, *args)

        total_users = await conn.fetchval(
            "SELECT COUNT(*)::int FROM users WHERE id_cat_rol = $1 AND is_active = true",
            row["id"]
        )

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="ACTUALIZAR_ROL",
        entidad="cat_roles",
        entidad_id=str(row["id"]),
        detalle=payload.model_dump(exclude_unset=True)
    )

    return RoleConfigResponse(
        id=str(row["id"]),
        descripcion=row["descripcion"],
        activo=row["activo"],
        total_usuarios=total_users or 0,
        updated_at=row["updated_at"]
    )
