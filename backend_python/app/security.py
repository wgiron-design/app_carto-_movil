import os
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, List
import jwt
from passlib.context import CryptContext
from fastapi import HTTPException, status, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import asyncpg
import uuid

from app.database import get_db_pool
from app.core.constants import normalize_role, ADMIN_ROLES

# Configuración de Hasher (argon2 como preferido, bcrypt como fallback)
pwd_context = CryptContext(schemes=["argon2", "bcrypt"], deprecated="auto")

SECRET_KEY = os.getenv("JWT_SECRET_KEY", "carto_digital_super_secret_jwt_key_2026_change_in_prod")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 # 24 horas

security = HTTPBearer(auto_error=False)

def hash_password(password: str) -> str:
    # Truncar a 72 bytes en caso de que se use bcrypt internamente como fallback
    return pwd_context.hash(password[:72])

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password[:72], hashed_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Dict[str, Any]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="El token de sesión ha expirado"
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de sesión inválido"
        )

async def get_current_user_claims(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> Dict[str, Any]:
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No se proporcionaron credenciales de autenticación"
        )
    return decode_access_token(credentials.credentials)

async def get_current_active_user(
    claims: Dict[str, Any] = Depends(get_current_user_claims),
    pool: asyncpg.Pool = Depends(get_db_pool)
) -> Dict[str, Any]:
    """
    Obtiene el usuario actual de la base de datos revalidando su estado activo y rol desde cat_roles.
    """
    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token no contiene identificador de usuario")
    
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Identificador de usuario inválido")

    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT 
                u.id, 
                u.username, 
                u.email, 
                COALESCE(r.descripcion, 'cartografo') as role,
                u.id_cat_rol,
                u.is_active, 
                u.id_jefe, 
                u.created_at, 
                u.last_login_at
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE u.id = $1
        """, user_uuid)

        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")

        if not row["is_active"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="usuario inactivo"
            )

        user_dict = dict(row)
        user_dict["id_supervisor"] = user_dict.get("id_jefe")
        return user_dict

def require_role(allowed_roles: List[str]):
    """
    Dependencia de FastAPI para RBAC estricto validado contra cat_roles en la base de datos.
    """
    normalized_allowed = {normalize_role(r) for r in allowed_roles}
    if "admin" in normalized_allowed or "administrador" in normalized_allowed:
        normalized_allowed.update(ADMIN_ROLES)

    async def role_checker(current_user: Dict[str, Any] = Depends(get_current_active_user)) -> Dict[str, Any]:
        user_role = normalize_role(str(current_user.get("role", "")))
        if user_role not in normalized_allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Acceso denegado. Se requiere uno de los siguientes roles: {', '.join(allowed_roles)}"
            )
        return current_user

    return role_checker
