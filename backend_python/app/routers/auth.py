from fastapi import APIRouter, HTTPException, status, Depends
import asyncpg
from typing import Dict, Any, List
from datetime import datetime, timezone
import uuid

from app.database import get_db_pool
from app.schemas.auth import (
    UserRegister,
    UserLogin,
    ForgotPasswordRequest,
    ResetPasswordRequest,
    UserResponse,
    TokenResponse,
    UserUpdateStatus,
    RoleEnum
)
from app.security import (
    hash_password,
    verify_password,
    create_access_token,
    get_current_user_claims
)
from app.core.constants import is_admin
from app.services.email_service import send_reset_password_email

router = APIRouter(prefix="/api/v1/auth", tags=["Autenticación"])


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: UserRegister, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    Registro de nuevos usuarios.
    Asigna automáticamente el rol 'cartografo' desde cat_roles.
    """
    async with pool.acquire() as conn:
        # Verificar duplicados
        existing = await conn.fetchrow("""
            SELECT username, email FROM users 
            WHERE LOWER(username) = LOWER($1) OR LOWER(email) = LOWER($2)
        """, payload.username, payload.email)

        if existing:
            if existing['username'].lower() == payload.username.lower():
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El nombre de usuario ya está registrado."
                )
            if existing['email'].lower() == payload.email.lower():
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="El correo electrónico ya está registrado."
                )

        # Buscar ID del rol cartógrafo en cat_roles
        role_row = await conn.fetchrow("""
            SELECT id, descripcion FROM cat_roles WHERE LOWER(descripcion) = 'cartografo'
        """)
        id_cat_rol = role_row['id'] if role_row else None

        pwd_hash = hash_password(payload.password)
        
        row = await conn.fetchrow("""
            INSERT INTO users (username, email, password_hash, id_cat_rol, is_active)
            VALUES ($1, $2, $3, $4, true)
            RETURNING id, username, email, id_cat_rol, is_active, created_at, last_login_at
        """, payload.username, payload.email, pwd_hash, id_cat_rol)

        return UserResponse(
            id=str(row['id']),
            username=row['username'],
            email=row['email'],
            role=role_row['descripcion'] if role_row else 'cartografo',
            id_cat_rol=str(row['id_cat_rol']) if row['id_cat_rol'] else None,
            is_active=row['is_active'],
            created_at=row['created_at'],
            last_login_at=row['last_login_at']
        )

@router.post("/login", response_model=TokenResponse)
async def login(payload: UserLogin, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    Autenticación de usuario.
    Verifica credenciales y estado activo contra users y cat_roles.
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                u.password_hash, 
                u.id_cat_rol,
                COALESCE(r.descripcion, 'cartografo') as role, 
                u.is_active, 
                u.created_at, 
                u.last_login_at 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE LOWER(u.username) = LOWER($1) OR LOWER(u.email) = LOWER($1)
        """, payload.username)

        if not row or not verify_password(payload.password, row['password_hash']):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Credenciales inválidas"
            )

        if not row['is_active']:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="usuario inactivo"
            )

        now = datetime.now(timezone.utc)
        await conn.execute("""
            UPDATE users SET last_login_at = $1 WHERE id = $2
        """, now, row['id'])

        user_obj = UserResponse(
            id=str(row['id']),
            username=row['username'],
            email=row['email'],
            role=row['role'],
            id_cat_rol=str(row['id_cat_rol']) if row['id_cat_rol'] else None,
            is_active=row['is_active'],
            created_at=row['created_at'],
            last_login_at=now
        )

        token = create_access_token({
            "sub": str(row['id']),
            "username": row['username'],
            "role": row['role']
        })

        return TokenResponse(
            access_token=token,
            token_type="bearer",
            user=user_obj
        )

@router.post("/forgot-password")
async def forgot_password(payload: ForgotPasswordRequest, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    Recuperación de contraseña.
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT id, username, email, is_active 
            FROM users 
            WHERE LOWER(username) = LOWER($1) AND LOWER(email) = LOWER($2)
        """, payload.username, payload.email)

        if row:
            reset_token = create_access_token({
                "sub": str(row['id']),
                "scope": "reset_password"
            })
            await send_reset_password_email(to_email=row['email'], username=row['username'], reset_token=reset_token)

        return {
            "message": "Si los datos ingresados coinciden con nuestros registros, se enviarán las instrucciones de recuperación a su correo electrónico."
        }

@router.post("/reset-password")
async def reset_password(payload: ResetPasswordRequest, pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    Restablece la contraseña utilizando un token válido.
    """
    from app.security import decode_access_token
    claims = decode_access_token(payload.token)
    
    if claims.get("scope") != "reset_password":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Token no válido para restablecimiento de contraseña."
        )

    user_id = claims.get("sub")
    pwd_hash = hash_password(payload.new_password)

    async with pool.acquire() as conn:
        result = await conn.execute("""
            UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2
        """, pwd_hash, uuid.UUID(user_id))

        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

    return {"message": "Contraseña restablecida exitosamente."}

@router.get("/me", response_model=UserResponse)
async def get_me(claims: Dict[str, Any] = Depends(get_current_user_claims), pool: asyncpg.Pool = Depends(get_db_pool)):
    """
    Retorna el perfil del usuario autenticado.
    """
    user_id = claims.get("sub")
    async with pool.acquire() as conn:
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
        """, uuid.UUID(user_id))

        if not row:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        if not row['is_active']:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="usuario inactivo"
            )

        return UserResponse(
            id=str(row['id']),
            username=row['username'],
            email=row['email'],
            role=row['role'],
            id_cat_rol=str(row['id_cat_rol']) if row['id_cat_rol'] else None,
            is_active=row['is_active'],
            created_at=row['created_at'],
            last_login_at=row['last_login_at']
        )

@router.patch("/users/{user_id}/status", response_model=UserResponse)
async def update_user_status(
    user_id: str,
    payload: UserUpdateStatus,
    claims: Dict[str, Any] = Depends(get_current_user_claims),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Endpoint administrativo para activar/desactivar usuario o cambiar rol.
    Requiere rol de 'admin' / 'administrador'.
    """
    if not is_admin(str(claims.get("role", ""))):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado. Se requiere rol de administrador."
        )

    async with pool.acquire() as conn:
        updates = []
        args = []
        idx = 1

        if payload.is_active is not None:
            updates.append(f"is_active = ${idx}")
            args.append(payload.is_active)
            idx += 1

        if payload.role is not None:
            role_row = await conn.fetchrow("SELECT id FROM cat_roles WHERE LOWER(descripcion) = LOWER($1)", payload.role.value)
            if not role_row:
                raise HTTPException(status_code=400, detail=f"Rol '{payload.role.value}' no existe en cat_roles.")
            updates.append(f"id_cat_rol = ${idx}")
            args.append(role_row['id'])
            idx += 1

        if not updates:
            raise HTTPException(status_code=400, detail="No se proporcionaron campos a actualizar.")

        updates.append("updated_at = NOW()")
        args.append(uuid.UUID(user_id))

        sql = f"""
            UPDATE users 
            SET {", ".join(updates)}
            WHERE id = ${idx}
            RETURNING id, username, email, id_cat_rol, is_active, created_at, last_login_at
        """
        row = await conn.fetchrow(sql, *args)

        if not row:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        role_desc = await conn.fetchval("SELECT descripcion FROM cat_roles WHERE id = $1", row['id_cat_rol'])

        return UserResponse(
            id=str(row['id']),
            username=row['username'],
            email=row['email'],
            role=role_desc or 'cartografo',
            id_cat_rol=str(row['id_cat_rol']) if row['id_cat_rol'] else None,
            is_active=row['is_active'],
            created_at=row['created_at'],
            last_login_at=row['last_login_at']
        )
