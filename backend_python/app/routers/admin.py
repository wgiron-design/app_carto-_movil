from fastapi import APIRouter, Request, Depends, Query
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
import os
import asyncpg
from typing import Dict, Any, Optional, List

from app.database import get_db_pool
from app.security import require_role

templates_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates")
templates = Jinja2Templates(directory=templates_dir)

router = APIRouter(tags=["Admin Web Panel"])

@router.get("/admin", response_class=HTMLResponse)
async def admin_dashboard(request: Request):
    return templates.TemplateResponse(request=request, name="admin.html")

@router.get("/reset-password-page", response_class=HTMLResponse)
async def reset_password_page(request: Request):
    return templates.TemplateResponse(request=request, name="reset_password.html")

@router.get("/api/v1/admin/stats")
async def get_admin_stats(
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Retorna métricas globales para el dashboard de administración.
    """
    async with pool.acquire() as conn:
        total_users = await conn.fetchval("SELECT COUNT(*) FROM users")
        active_users = await conn.fetchval("SELECT COUNT(*) FROM users WHERE is_active = true")
        total_upms = await conn.fetchval("SELECT COUNT(*) FROM upms WHERE deleted_at IS NULL")
        upms_assigned_sup = await conn.fetchval("""
            SELECT COUNT(DISTINCT au.id_upm) 
            FROM asignacion_upms au
            JOIN upms u ON au.id_upm = u.id AND u.deleted_at IS NULL
            WHERE au.rol_asignacion = 'supervisor'
        """)
        upms_assigned_cart = await conn.fetchval("""
            SELECT COUNT(DISTINCT au.id_upm) 
            FROM asignacion_upms au
            JOIN upms u ON au.id_upm = u.id AND u.deleted_at IS NULL
            WHERE au.rol_asignacion = 'cartografo'
        """)
        total_audits = await conn.fetchval("SELECT COUNT(*) FROM audit_log")

        roles_distribution = await conn.fetch("""
            SELECT COALESCE(r.descripcion, 'sin_rol') as role, COUNT(u.id)::int as count 
            FROM users u
            LEFT JOIN cat_roles r ON u.id_cat_rol = r.id
            WHERE u.is_active = true 
            GROUP BY r.descripcion
        """)

        recent_audits = await conn.fetch("""
            SELECT 
                al.id, 
                al.accion, 
                al.entidad, 
                al.creado_en,
                u.username as actor_username
            FROM audit_log al
            LEFT JOIN users u ON al.id_actor = u.id
            ORDER BY al.creado_en DESC
            LIMIT 6
        """)

    return {
        "total_users": total_users or 0,
        "active_users": active_users or 0,
        "total_upms": total_upms or 0,
        "upms_assigned_supervisor": upms_assigned_sup or 0,
        "upms_assigned_cartografo": upms_assigned_cart or 0,
        "total_audits": total_audits or 0,
        "roles_distribution": {r["role"]: r["count"] for r in roles_distribution},
        "recent_audits": [
            {
                "id": str(r["id"]),
                "accion": r["accion"],
                "entidad": r["entidad"],
                "actor_username": r["actor_username"] or "Sistema",
                "creado_en": r["creado_en"]
            }
            for r in recent_audits
        ]
    }

@router.get("/api/v1/admin/audit-log")
async def get_audit_log(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    entidad: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(require_role(["admin", "administrador"])),
    pool: asyncpg.Pool = Depends(get_db_pool)
):
    """
    Lista el historial de eventos de auditoría.
    """
    conditions = []
    args = []
    idx = 1

    if entidad:
        conditions.append(f"al.entidad = ${idx}")
        args.append(entidad)
        idx += 1

    where_clause = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    async with pool.acquire() as conn:
        count_sql = f"SELECT COUNT(*) FROM audit_log al {where_clause}"
        total = await conn.fetchval(count_sql, *args)

        query_sql = f"""
            SELECT 
                al.id, 
                al.id_actor, 
                u.username as actor_username,
                al.accion, 
                al.entidad, 
                al.entidad_id, 
                al.detalle, 
                al.creado_en
            FROM audit_log al
            LEFT JOIN users u ON al.id_actor = u.id
            {where_clause}
            ORDER BY al.creado_en DESC
            LIMIT ${idx} OFFSET ${idx + 1}
        """
        rows = await conn.fetch(query_sql, *args, limit, offset)

    return {
        "total": total,
        "items": [
            {
                "id": str(r["id"]),
                "id_actor": str(r["id_actor"]) if r["id_actor"] else None,
                "actor_username": r["actor_username"] or "Sistema",
                "accion": r["accion"],
                "entidad": r["entidad"],
                "entidad_id": r["entidad_id"],
                "detalle": r["detalle"],
                "creado_en": r["creado_en"]
            }
            for r in rows
        ]
    }
