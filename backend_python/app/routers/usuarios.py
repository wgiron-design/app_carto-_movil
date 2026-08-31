from fastapi import APIRouter, HTTPException, status, Depends, Query
import asyncpg
from typing import Optional, Dict, Any, List
import uuid
import math

from app.database import get_db_pool
from app.security import require_role, hash_password
from app.core.constants import is_admin, ADMIN_ROLES
from app.schemas.usuarios import (
    UserAdminCreate,
    UserAdminUpdate,
    UserAdminItem,
    PaginatedUsersResponse
)
from app.services.auditoria import registrar_auditoria

router = APIRouter(prefix="/api/v1/admin/usuarios", tags=["Admin - Usuarios"])

@router.get("", response_model=PaginatedUsersResponse)
async def list_users(
    search: Optional[str] = Query(None, description="Búsqueda por username o email"),
    role: Optional[str] = Query(None, description="Filtrar por rol"),
    is_active: Optional[bool] = Query(None, description="Filtrar por estado activo"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Lista usuarios con paginación, filtros de búsqueda, estado y visualización de su rol y supervisor.
    """
    offset = (page - 1) * page_size
    conditions = []
    args = []
    idx = 1

    if search:
        s = f"%{search.strip()}%"
        conditions.append(f"(u.username ILIKE ${idx} OR u.email ILIKE ${idx})")
        args.append(s)
        idx += 1

    if role:
        conditions.append(f"LOWER(r.descripcion) = LOWER(${idx})")
        args.append(role.strip())
        idx += 1

    if is_active is not None:
        conditions.append(f"u.is_active = ${idx}")
        args.append(is_active)
        idx += 1

    where_clause = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    async with pool.acquire() as conn:
        count_sql = f"""
            SELECT COUNT(*) 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            {where_clause}
        """
        total = await conn.fetchval(count_sql, *args)

        query_sql = f"""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                COALESCE(r.descripcion, 'cartografo') as role, 
                u.id_cat_rol,
                u.is_active, 
                u.id_jefe, 
                jefe.username as jefe_username,
                u.created_at, 
                u.last_login_at
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            LEFT JOIN users jefe ON u.id_jefe = jefe.id
            {where_clause}
            ORDER BY u.created_at DESC
            LIMIT ${idx} OFFSET ${idx + 1}
        """
        rows = await conn.fetch(query_sql, *args, page_size, offset)

    items = [
        UserAdminItem(
            id=str(r["id"]),
            username=r["username"],
            email=r["email"],
            role=r["role"],
            id_cat_rol=str(r["id_cat_rol"]) if r["id_cat_rol"] else None,
            is_active=r["is_active"],
            id_jefe=str(r["id_jefe"]) if r["id_jefe"] else None,
            jefe_username=r["jefe_username"],
            created_at=r["created_at"],
            last_login_at=r["last_login_at"]
        )
        for r in rows
    ]

    total_pages = math.ceil(total / page_size) if total > 0 else 1

    return PaginatedUsersResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages
    )

@router.post("", response_model=UserAdminItem, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserAdminCreate,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Crea un nuevo usuario desde el panel administrativo.
    """
    async with pool.acquire() as conn:
        existing = await conn.fetchrow("""
            SELECT username, email FROM users 
            WHERE LOWER(username) = LOWER($1) OR LOWER(email) = LOWER($2)
        """, payload.username, payload.email)

        if existing:
            if existing["username"].lower() == payload.username.lower():
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="El nombre de usuario ya está registrado.")
            if existing["email"].lower() == payload.email.lower():
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="El correo electrónico ya está registrado.")

        # Obtener rol
        role_uuid = None
        if payload.id_cat_rol:
            try:
                role_uuid = uuid.UUID(payload.id_cat_rol)
            except ValueError:
                raise HTTPException(status_code=400, detail="ID de rol inválido.")
        else:
            role_row = await conn.fetchrow("SELECT id FROM cat_roles WHERE LOWER(descripcion) = LOWER($1)", payload.role)
            if role_row:
                role_uuid = role_row["id"]
            else:
                # Fallback al primer rol o cartógrafo
                role_uuid = await conn.fetchval("SELECT id FROM cat_roles LIMIT 1")

        jefe_uuid = None
        if payload.id_jefe:
            try:
                jefe_uuid = uuid.UUID(payload.id_jefe)
                jefe = await conn.fetchrow("SELECT id FROM users WHERE id = $1 AND is_active = true", jefe_uuid)
                if not jefe:
                    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="El jefe especificado no existe o está inactivo.")
            except ValueError:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ID de jefe inválido.")

        pwd_hash = hash_password(payload.password)

        row = await conn.fetchrow("""
            INSERT INTO users (username, email, password_hash, id_cat_rol, id_jefe, is_active)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id, username, email, id_cat_rol, is_active, id_jefe, created_at, last_login_at
        """, payload.username, payload.email, pwd_hash, role_uuid, jefe_uuid, payload.is_active)

        role_desc = await conn.fetchval("SELECT descripcion FROM cat_roles WHERE id = $1", row["id_cat_rol"])
        jefe_username = None
        if jefe_uuid:
            jefe_username = await conn.fetchval("SELECT username FROM users WHERE id = $1", jefe_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="CREAR_USUARIO",
        entidad="users",
        entidad_id=str(row["id"]),
        detalle={"username": payload.username, "email": payload.email, "role": role_desc}
    )

    return UserAdminItem(
        id=str(row["id"]),
        username=row["username"],
        email=row["email"],
        role=role_desc or 'cartografo',
        id_cat_rol=str(row["id_cat_rol"]) if row["id_cat_rol"] else None,
        is_active=row["is_active"],
        id_jefe=str(row["id_jefe"]) if row["id_jefe"] else None,
        jefe_username=jefe_username,
        created_at=row["created_at"],
        last_login_at=row["last_login_at"]
    )

@router.patch("/{user_id}", response_model=UserAdminItem)
async def update_user(
    user_id: str,
    payload: UserAdminUpdate,
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Modifica un usuario (email, rol, estado activo, supervisor o contraseña).
    REGLA DE BORRADO LÓGICO: Los endpoints DELETE no existen; se usa is_active=false.
    """
    try:
        target_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ID de usuario inválido.")

    async with pool.acquire() as conn:
        current_target = await conn.fetchrow("""
            SELECT u.id, u.username, u.email, u.id_cat_rol, r.descripcion as role, u.is_active 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE u.id = $1
        """, target_uuid)
        if not current_target:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado.")

        # Si el usuario intenta desactivarse a sí mismo o quitarse admin siendo el único
        if str(current_user["id"]) == str(target_uuid):
            if payload.is_active is False:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No puedes desactivar tu propia cuenta de administrador.")

        updates = []
        args = []
        idx = 1

        if payload.email:
            existing_email = await conn.fetchrow(
                "SELECT id FROM users WHERE LOWER(email) = LOWER($1) AND id != $2",
                payload.email, target_uuid
            )
            if existing_email:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="El correo ya pertenece a otro usuario.")
            updates.append(f"email = ${idx}")
            args.append(payload.email)
            idx += 1

        if payload.id_cat_rol:
            try:
                r_uuid = uuid.UUID(payload.id_cat_rol)
                updates.append(f"id_cat_rol = ${idx}")
                args.append(r_uuid)
                idx += 1
            except ValueError:
                raise HTTPException(status_code=400, detail="UUID de rol inválido.")
        elif payload.role:
            role_row = await conn.fetchrow("SELECT id FROM cat_roles WHERE LOWER(descripcion) = LOWER($1)", payload.role.strip())
            if role_row:
                updates.append(f"id_cat_rol = ${idx}")
                args.append(role_row["id"])
                idx += 1

        if payload.id_jefe is not None:
            if payload.id_jefe == "":
                updates.append("id_jefe = NULL")
            else:
                try:
                    jefe_uuid = uuid.UUID(payload.id_jefe)
                    if jefe_uuid == target_uuid:
                        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Un usuario no puede ser su propio jefe.")
                    updates.append(f"id_jefe = ${idx}")
                    args.append(jefe_uuid)
                    idx += 1
                except ValueError:
                    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ID de jefe inválido.")

        if payload.is_active is not None:
            updates.append(f"is_active = ${idx}")
            args.append(payload.is_active)
            idx += 1

        if payload.password:
            pwd_hash = hash_password(payload.password)
            updates.append(f"password_hash = ${idx}")
            args.append(pwd_hash)
            idx += 1

        if not updates:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No se enviaron campos a modificar.")

        updates.append("updated_at = NOW()")
        args.append(target_uuid)

        sql = f"""
            UPDATE users
            SET {', '.join(updates)}
            WHERE id = ${idx}
            RETURNING id, username, email, id_cat_rol, is_active, id_jefe, created_at, last_login_at
        """
        row = await conn.fetchrow(sql, *args)

        role_desc = await conn.fetchval("SELECT descripcion FROM cat_roles WHERE id = $1", row["id_cat_rol"])
        jefe_username = None
        if row["id_jefe"]:
            jefe_username = await conn.fetchval("SELECT username FROM users WHERE id = $1", row["id_jefe"])

    await registrar_auditoria(
        pool=pool,
        id_actor=str(current_user["id"]),
        accion="MODIFICAR_USUARIO",
        entidad="users",
        entidad_id=user_id,
        detalle=payload.model_dump(exclude_unset=True, exclude={"password"})
    )

    return UserAdminItem(
        id=str(row["id"]),
        username=row["username"],
        email=row["email"],
        role=role_desc or 'cartografo',
        id_cat_rol=str(row["id_cat_rol"]) if row["id_cat_rol"] else None,
        is_active=row["is_active"],
        id_jefe=str(row["id_jefe"]) if row["id_jefe"] else None,
        jefe_username=jefe_username,
        created_at=row["created_at"],
        last_login_at=row["last_login_at"]
    )
