from fastapi import APIRouter, HTTPException, status, Depends
import asyncpg
from typing import Dict, Any
import uuid

from app.database import get_db_pool
from app.security import get_current_active_user, verify_password, hash_password
from app.schemas.mi_cuenta import UpdateUsernameRequest, UpdateEmailRequest, UpdatePasswordRequest
from app.schemas.auth import UserResponse
from app.services.auditoria import registrar_auditoria

router = APIRouter(prefix="/api/v1/auth/me", tags=["Mi Cuenta"])

@router.patch("/username", response_model=UserResponse)
async def update_my_username(
    payload: UpdateUsernameRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Actualiza el nombre de usuario del usuario autenticado.
    """
    user_uuid = uuid.UUID(str(current_user["id"]))
    new_username = payload.new_username.strip()

    async with pool.acquire() as conn:
        existing = await conn.fetchrow(
            "SELECT id FROM users WHERE LOWER(username) = LOWER($1) AND id != $2",
            new_username, user_uuid
        )
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El nombre de usuario ya está registrado por otro usuario."
            )

        await conn.execute("""
            UPDATE users 
            SET username = $1, updated_at = NOW() 
            WHERE id = $2
        """, new_username, user_uuid)

        row = await conn.fetchrow("""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                COALESCE(r.descripcion, 'cartografo') as role, 
                u.id_cat_rol,
                u.is_active, 
                u.created_at, 
                u.last_login_at 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE u.id = $1
        """, user_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(user_uuid),
        accion="CAMBIO_USERNAME_PROPIO",
        entidad="users",
        entidad_id=str(user_uuid),
        detalle={"old_username": current_user["username"], "new_username": new_username}
    )

    return UserResponse(
        id=str(row["id"]),
        username=row["username"],
        email=row["email"],
        role=row["role"],
        id_cat_rol=str(row["id_cat_rol"]) if row["id_cat_rol"] else None,
        is_active=row["is_active"],
        created_at=row["created_at"],
        last_login_at=row["last_login_at"]
    )

@router.patch("/email", response_model=UserResponse)
async def update_my_email(
    payload: UpdateEmailRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Actualiza el correo electrónico del usuario autenticado.
    """
    user_uuid = uuid.UUID(str(current_user["id"]))
    new_email = payload.new_email.strip()

    async with pool.acquire() as conn:
        existing = await conn.fetchrow(
            "SELECT id FROM users WHERE LOWER(email) = LOWER($1) AND id != $2",
            new_email, user_uuid
        )
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El correo electrónico ya está registrado por otro usuario."
            )

        await conn.execute("""
            UPDATE users 
            SET email = $1, updated_at = NOW() 
            WHERE id = $2
        """, new_email, user_uuid)

        row = await conn.fetchrow("""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                COALESCE(r.descripcion, 'cartografo') as role, 
                u.id_cat_rol,
                u.is_active, 
                u.created_at, 
                u.last_login_at 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE u.id = $1
        """, user_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(user_uuid),
        accion="CAMBIO_EMAIL_PROPIO",
        entidad="users",
        entidad_id=str(user_uuid),
        detalle={"old_email": current_user["email"], "new_email": new_email}
    )

    return UserResponse(
        id=str(row["id"]),
        username=row["username"],
        email=row["email"],
        role=row["role"],
        id_cat_rol=str(row["id_cat_rol"]) if row["id_cat_rol"] else None,
        is_active=row["is_active"],
        created_at=row["created_at"],
        last_login_at=row["last_login_at"]
    )

@router.patch("/password")
async def update_my_password(
    payload: UpdatePasswordRequest,
    current_user: Dict[str, Any] = Depends(get_current_active_user),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Cambio de contraseña propio.
    Requiere password actual, nueva password y confirmación.
    Valida longitud mínima >= 6 caracteres.
    """
    if payload.new_password != payload.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La nueva contraseña y la confirmación no coinciden."
        )

    if len(payload.new_password) < 5:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="La nueva contraseña debe tener al menos 5 caracteres."
        )

    user_uuid = uuid.UUID(str(current_user["id"]))

    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT password_hash FROM users WHERE id = $1", user_uuid)
        if not row or not verify_password(payload.current_password, row["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="La contraseña actual ingresada es incorrecta."
            )

        new_hash = hash_password(payload.new_password)
        await conn.execute("""
            UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2
        """, new_hash, user_uuid)

    await registrar_auditoria(
        pool=pool,
        id_actor=str(user_uuid),
        accion="CAMBIO_PASSWORD_PROPIO",
        entidad="users",
        entidad_id=str(user_uuid)
    )

    return {"success": True, "message": "Contraseña actualizada exitosamente."}
