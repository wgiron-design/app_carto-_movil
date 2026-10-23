import json
import uuid
import logging
import asyncpg
from fastapi import APIRouter, HTTPException, Query, Depends
from typing import Optional, Dict, Any, List
from datetime import datetime
from app.database import get_db_pool
from app.security import get_current_active_user
from app.core.constants import is_admin, normalize_role

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/capas", tags=["Geometrias GeoJSON"])

TABLAS_PERMITIDAS = {"estructuras", "caminos", "upms"}
TABLAS_GENERICAS = {"estructuras", "caminos"}

# IDs de tipos válidos en cat_estructuras_tipo (1=Formal, 2=Referencia).
# Si el catálogo crece, actualizar también esta constante o convertirla en
# una consulta dinámica al pool en el startup del servidor.
TIPOS_ESTRUCTURA_VALIDOS: List[int] = [1, 2]

def parse_uuid_or_none(val: Any) -> Optional[str]:
    """Valida y convierte cualquier valor a un string UUID válido o retorna None."""
    if not val:
        return None
    val_str = str(val).strip()
    if val_str in ("", "null", "undefined", "None"):
        return None
    try:
        return str(uuid.UUID(val_str))
    except (ValueError, AttributeError, TypeError):
        return None


def parse_int_or_none(val: Any) -> Optional[int]:
    """Valida y convierte un valor a entero o retorna None."""
    if val is None:
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


# ----------------------------------------------------------------------
# Endpoints dedicados para UPMs con RBAC y filtro estricto por asignación
# ----------------------------------------------------------------------

@router.get("/upms/features")
async def get_upms_features(
    bbox: Optional[str] = None,
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Retorna las UPMs activas en formato GeoJSON FeatureCollection.
    - Admins: ven todas las UPMs activas.
    - Supervisores: ven únicamente las UPMs asignadas con rol_asignacion = 'supervisor'.
    - Cartógrafos (y demás roles no-admin): ven únicamente las asignadas con rol_asignacion = 'cartografo'.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    user_uuid = uuid.UUID(str(current_user["id"]))

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        where_parts = ["t.deleted_at IS NULL"]
        args = []
        arg_idx = 1
        join_clause = ""

        if not is_admin(user_role):
            rol_asig = "supervisor" if user_role == "supervisor" else "cartografo"
            join_clause = f"JOIN asignacion_upms au ON t.id = au.id_upm AND au.rol_asignacion = ${arg_idx} AND au.id_usuario = ${arg_idx+1}"
            args.extend([rol_asig, user_uuid])
            arg_idx += 2

        if bbox:
            try:
                parts = [float(x) for x in bbox.split(",")]
                if len(parts) == 4:
                    where_parts.append(
                        f"ST_Intersects(t.geom, ST_MakeEnvelope(${arg_idx}, ${arg_idx+1}, ${arg_idx+2}, ${arg_idx+3}, 4326))"
                    )
                    args.extend(parts)
                    arg_idx += 4
            except Exception:
                pass

        where_clause = "WHERE " + " AND ".join(where_parts)

        sql = f"""
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features', COALESCE(json_agg(
                json_build_object(
                    'type', 'Feature',
                    'id', t.id::text,
                    'geometry', ST_AsGeoJSON(t.geom)::json,
                    'properties', to_jsonb(t.*) - 'geom'
                )
            ), '[]'::json)
        ) AS geojson
        FROM upms t
        {join_clause}
        {where_clause};
        """
        row = await conn.fetchrow(sql, *args)
        return json.loads(row['geojson'])


@router.get("/upms/features/changes")
async def get_upms_changes(
    since: str = Query(..., description="ISO 8601 timestamp. Retorna UPMs asignadas modificadas o eliminadas desde esta fecha."),
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Delta-sync para UPMs asignadas al usuario actual.
    """
    user_role = normalize_role(str(current_user.get("role", "")))
    user_uuid = uuid.UUID(str(current_user["id"]))

    try:
        since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=400, detail="Formato de fecha inválido. Use ISO 8601 (ej: 2026-08-01T00:00:00Z)")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        join_clause = ""
        args = [since_dt]

        if not is_admin(user_role):
            rol_asig = "supervisor" if user_role == "supervisor" else "cartografo"
            join_clause = "JOIN asignacion_upms au ON t.id = au.id_upm AND au.rol_asignacion = $2 AND au.id_usuario = $3"
            args.extend([rol_asig, user_uuid])

        sql = f"""
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features', COALESCE(json_agg(
                json_build_object(
                    'type', 'Feature',
                    'id', t.id::text,
                    'geometry', CASE WHEN t.deleted_at IS NULL THEN ST_AsGeoJSON(t.geom)::json ELSE NULL END,
                    'properties', to_jsonb(t.*) - 'geom',
                    'deleted', (t.deleted_at IS NOT NULL)
                )
            ), '[]'::json)
        ) AS geojson
        FROM upms t
        {join_clause}
        WHERE t.updated_at > $1;
        """
        row = await conn.fetchrow(sql, *args)
        return json.loads(row['geojson'])


@router.get("/upms/count")
async def get_upms_count(
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """Retorna el conteo de UPMs activas asignadas al usuario."""
    user_role = normalize_role(str(current_user.get("role", "")))
    user_uuid = uuid.UUID(str(current_user["id"]))

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        if is_admin(user_role):
            row = await conn.fetchrow("SELECT COUNT(*) as count FROM upms WHERE deleted_at IS NULL;")
        else:
            rol_asig = "supervisor" if user_role == "supervisor" else "cartografo"
            row = await conn.fetchrow("""
                SELECT COUNT(DISTINCT t.id) as count 
                FROM upms t
                JOIN asignacion_upms au ON t.id = au.id_upm AND au.rol_asignacion = $1 AND au.id_usuario = $2
                WHERE t.deleted_at IS NULL;
            """, rol_asig, user_uuid)
        return {"count": row['count']}


@router.get("/{tabla}/features")
async def get_features(tabla: str, bbox: Optional[str] = None):
    """Retorna features activos (excluye soft-deleted) como GeoJSON FeatureCollection para tablas genéricas."""
    if tabla == "upms":
        raise HTTPException(
            status_code=400,
            detail="Las UPMs requieren autenticación. Utilice el endpoint autenticado /api/capas/upms/features"
        )
    if tabla not in TABLAS_GENERICAS:
        raise HTTPException(status_code=400, detail="Tabla no autorizada")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        where_parts = ["t.deleted_at IS NULL"]
        args = []
        arg_idx = 1

        if bbox:
            try:
                parts = [float(x) for x in bbox.split(",")]
                if len(parts) == 4:
                    where_parts.append(
                        f"ST_Intersects(t.geom, ST_MakeEnvelope(${arg_idx}, ${arg_idx+1}, ${arg_idx+2}, ${arg_idx+3}, 4326))"
                    )
                    args.extend(parts)
                    arg_idx += 4
            except Exception:
                pass

        where_clause = "WHERE " + " AND ".join(where_parts)

        if tabla == "estructuras":
            sql = f"""
            SELECT json_build_object(
                'type', 'FeatureCollection',
                'features', COALESCE(json_agg(
                    json_build_object(
                        'type', 'Feature',
                        'id', t.id::text,
                        'geometry', ST_AsGeoJSON(t.geom)::json,
                        'properties', (to_jsonb(t.*) - 'geom') || jsonb_build_object(
                            'nombre_categoria', c.nombre,
                            'nombre_tipo', tp.nombre
                        )
                    )
                ), '[]'::json)
            ) AS geojson
            FROM estructuras t
            LEFT JOIN cat_estructuras_categoria c ON c.id = t.id_categoria
            LEFT JOIN cat_estructuras_tipo tp ON tp.id = t.id_tipo
            {where_clause};
            """
        else:
            sql = f"""
            SELECT json_build_object(
                'type', 'FeatureCollection',
                'features', COALESCE(json_agg(
                    json_build_object(
                        'type', 'Feature',
                        'id', id::text,
                        'geometry', ST_AsGeoJSON(geom)::json,
                        'properties', to_jsonb(t.*) - 'geom'
                    )
                ), '[]'::json)
            ) AS geojson
            FROM {tabla} t {where_clause};
            """
        row = await conn.fetchrow(sql, *args)
        return json.loads(row['geojson'])


@router.get("/{tabla}/features/changes")
async def get_changes(
    tabla: str,
    since: str = Query(..., description="ISO 8601 timestamp. Retorna registros modificados o eliminados desde esta fecha.")
):
    """
    Delta-sync: retorna todos los registros (activos y soft-deleted) modificados desde `since`.
    La app usa esto para sincronizar cambios del servidor hacia el dispositivo.
    """
    if tabla == "upms":
        raise HTTPException(
            status_code=400,
            detail="Las UPMs requieren autenticación. Utilice el endpoint autenticado /api/capas/upms/features/changes"
        )
    if tabla not in TABLAS_GENERICAS:
        raise HTTPException(status_code=400, detail="Tabla no autorizada")

    try:
        since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=400, detail="Formato de fecha inválido. Use ISO 8601 (ej: 2026-08-01T00:00:00Z)")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        if tabla == "estructuras":
            sql = """
            SELECT json_build_object(
                'type', 'FeatureCollection',
                'features', COALESCE(json_agg(
                    json_build_object(
                        'type', 'Feature',
                        'id', t.id::text,
                        'geometry', CASE WHEN t.deleted_at IS NULL THEN ST_AsGeoJSON(t.geom)::json ELSE NULL END,
                        'properties', (to_jsonb(t.*) - 'geom') || jsonb_build_object(
                            'nombre_categoria', c.nombre,
                            'nombre_tipo', tp.nombre
                        ),
                        'deleted', (t.deleted_at IS NOT NULL)
                    )
                ), '[]'::json)
            ) AS geojson
            FROM estructuras t
            LEFT JOIN cat_estructuras_categoria c ON c.id = t.id_categoria
            LEFT JOIN cat_estructuras_tipo tp ON tp.id = t.id_tipo
            WHERE t.updated_at > $1;
            """
        else:
            sql = f"""
            SELECT json_build_object(
                'type', 'FeatureCollection',
                'features', COALESCE(json_agg(
                    json_build_object(
                        'type', 'Feature',
                        'id', id::text,
                        'geometry', CASE WHEN deleted_at IS NULL THEN ST_AsGeoJSON(geom)::json ELSE NULL END,
                        'properties', to_jsonb(t.*) - 'geom',
                        'deleted', (deleted_at IS NOT NULL)
                    )
                ), '[]'::json)
            ) AS geojson
            FROM {tabla} t
            WHERE updated_at > $1;
            """
        row = await conn.fetchrow(sql, since_dt)
        return json.loads(row['geojson'])


@router.get("/{tabla}/count")
async def get_count(tabla: str):
    """Retorna el conteo de features activos."""
    if tabla == "upms":
        raise HTTPException(
            status_code=400,
            detail="Las UPMs requieren autenticación. Utilice el endpoint autenticado /api/capas/upms/count"
        )
    if tabla not in TABLAS_GENERICAS:
        raise HTTPException(status_code=400, detail="Tabla no autorizada")

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(f"SELECT COUNT(*) as count FROM {tabla} WHERE deleted_at IS NULL;")
        return {"count": row['count']}


async def propietario_elemento(conn, tabla: str, feature_id: Optional[str], current_user_id: Optional[str]) -> bool:
    """
    Compara el usuario en sesión contra el campo created_by del elemento seleccionado.
    Si coincide -> True, si no -> False.
    """
    clean_fid = parse_uuid_or_none(feature_id)
    clean_uid = parse_uuid_or_none(current_user_id)
    if not clean_fid:
        return True

    try:
        row = await conn.fetchrow(f"SELECT created_by::text FROM {tabla} WHERE id = $1::uuid", clean_fid)
        if not row or not row['created_by']:
            return True
        if not clean_uid:
            return False
        return str(row['created_by']) == str(clean_uid)
    except Exception as e:
        logger.warning(f"Error comprobando propietario_elemento: {e}")
        return True


@router.post("/{tabla}/features")
async def create_feature(tabla: str, payload: Dict[str, Any]):
    """
    Crea o actualiza un feature. Si se provee `id`, hace UPSERT.
    Acepta `created_by`, `updated_by` y `device_id` en `properties`.
    """
    if tabla not in TABLAS_PERMITIDAS:
        raise HTTPException(status_code=400, detail="Tabla no autorizada")

    geometry = payload.get("geometry")
    properties = payload.get("properties", {})
    
    feature_id = parse_uuid_or_none(payload.get("id"))
    created_by = parse_uuid_or_none(properties.get("created_by"))
    updated_by = parse_uuid_or_none(properties.get("updated_by"))
    device_id  = properties.get("device_id") or None

    if not geometry:
        raise HTTPException(status_code=400, detail="Geometría requerida")

    geom_json = json.dumps(geometry)

    pool = await get_db_pool()

    async with pool.acquire() as conn:
        # Si es actualización (id provisto y existe en BD), validar propiedad del elemento
        if feature_id:
            es_dueno = await propietario_elemento(conn, tabla, feature_id, updated_by or created_by)
            if not es_dueno:
                raise HTTPException(status_code=403, detail="Ud. no creo este elemento, no tiene permisos de edición")

        # Validación de topología previa a inserción/actualización
        try:
            is_valid = await conn.fetchval("SELECT ST_IsValid(ST_GeomFromGeoJSON($1))", geom_json)
            if is_valid is False:
                raise HTTPException(status_code=422, detail="Geometría inválida: auto-intersección o topología corrupta")
        except HTTPException:
            raise
        except Exception as e:
            logger.warning(f"No se pudo validar ST_IsValid: {e}")

        logger.info(f"[AUDIT GEOMETRIA] Guardando feature en {tabla} - ID: {feature_id}, Modificado por: {updated_by or created_by or 'Anónimo'}")

        if tabla == "estructuras":
            id_categoria = parse_int_or_none(properties.get("id_categoria"))
            id_tipo = parse_int_or_none(properties.get("id_tipo"))

            if id_categoria is None or id_tipo is None:
                raise HTTPException(
                    status_code=422,
                    detail="id_categoria e id_tipo son requeridos y deben ser enteros válidos"
                )

            # ── Validación cruzada: la categoría debe pertenecer al tipo indicado ──────
            # Query parametrizada — nunca concatenar id_categoria o id_tipo en el SQL.
            cat_valida = await conn.fetchval(
                "SELECT 1 FROM cat_estructuras_categoria WHERE id = $1 AND tipo = $2",
                id_categoria, id_tipo
            )
            if cat_valida is None:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"La categoría seleccionada (id={id_categoria}) no corresponde "
                        f"al tipo de estructura indicado (id_tipo={id_tipo}). "
                        "Verifique que la categoría pertenezca al tipo correcto."
                    )
                )

            id_estructura_user = parse_int_or_none(properties.get("id_estructura_user"))

            sql = """
            INSERT INTO estructuras (
                id, geom, nombre, notas, id_categoria, id_tipo, id_estructura_user,
                estado, niveles_cantidad, created_by, updated_by, device_id, sync_version
            )
            VALUES (
                COALESCE($1::uuid, uuid_generate_v4()), ST_GeomFromGeoJSON($2),
                $3, $4, $5, $6, $7, $8, $9,
                $10::uuid, $11::uuid, $12, 0
            )
            ON CONFLICT (id) DO UPDATE SET
                geom = ST_GeomFromGeoJSON($2),
                nombre = $3, notas = $4, id_categoria = $5,
                id_tipo = $6, id_estructura_user = $7, estado = $8,
                niveles_cantidad = $9,
                created_by = COALESCE(estructuras.created_by, EXCLUDED.created_by),
                updated_by = $11::uuid, device_id = $12,
                sync_version = estructuras.sync_version + 1,
                updated_at = NOW(),
                deleted_at = NULL
            RETURNING
                id::text, ST_AsGeoJSON(geom)::json AS geometry,
                nombre, notas, id_categoria, id_tipo, id_estructura_user,
                estado, niveles_cantidad, sync_version,
                created_by::text, updated_by::text, device_id;
            """
            try:
                row = await conn.fetchrow(
                    sql, feature_id, geom_json,
                    properties.get("nombre"), properties.get("notas"),
                    id_categoria, id_tipo, id_estructura_user, properties.get("estado"),
                    parse_int_or_none(properties.get("niveles_cantidad")) or 1,
                    created_by, updated_by, device_id
                )
            except asyncpg.exceptions.RaiseError as e:
                raise HTTPException(
                    status_code=400,
                    detail=f"Error en validación espacial de la base de datos: {e.message if hasattr(e, 'message') else str(e)}"
                )
            except asyncpg.exceptions.ForeignKeyViolationError as e:
                raise HTTPException(
                    status_code=422,
                    detail=f"Error de llave foránea: id_categoria o id_tipo no existen en los catálogos ({e.detail})"
                )
        elif tabla == "caminos":
            sql = """
            INSERT INTO caminos (id, geom, nombre, tipo, notas, created_by, updated_by, device_id, sync_version)
            VALUES (COALESCE($1::uuid, uuid_generate_v4()), ST_GeomFromGeoJSON($2), $3, $4, $5, $6::uuid, $7::uuid, $8, 0)
            ON CONFLICT (id) DO UPDATE SET
                geom = ST_GeomFromGeoJSON($2), nombre = $3, tipo = $4, notas = $5,
                created_by = COALESCE(caminos.created_by, EXCLUDED.created_by),
                updated_by = $7::uuid, device_id = $8,
                sync_version = caminos.sync_version + 1,
                updated_at = NOW(), deleted_at = NULL
            RETURNING id::text, ST_AsGeoJSON(geom)::json AS geometry,
                nombre, tipo, notas, sync_version,
                created_by::text, updated_by::text, device_id;
            """
            row = await conn.fetchrow(
                sql, feature_id, geom_json,
                properties.get("nombre"), properties.get("tipo"), properties.get("notas"),
                created_by, updated_by, device_id
            )
        elif tabla == "upms":
            sql = """
            INSERT INTO upms (id, geom, nombre, codigo_upm, notas, created_by, updated_by, device_id, sync_version)
            VALUES (COALESCE($1::uuid, uuid_generate_v4()), ST_GeomFromGeoJSON($2), $3, $4, $5, $6::uuid, $7::uuid, $8, 0)
            ON CONFLICT (id) DO UPDATE SET
                geom = ST_GeomFromGeoJSON($2), nombre = $3, codigo_upm = $4, notas = $5,
                created_by = COALESCE(upms.created_by, EXCLUDED.created_by),
                updated_by = $7::uuid, device_id = $8,
                sync_version = upms.sync_version + 1,
                updated_at = NOW(), deleted_at = NULL
            RETURNING id::text, ST_AsGeoJSON(geom)::json AS geometry,
                nombre, codigo_upm, notas, sync_version,
                created_by::text, updated_by::text, device_id;
            """
            row = await conn.fetchrow(
                sql, feature_id, geom_json,
                properties.get("nombre"), properties.get("codigo_upm"), properties.get("notas"),
                created_by, updated_by, device_id
            )

        res = dict(row)
        geom = json.loads(res.pop("geometry"))
        fid = res.pop("id")
        return {"type": "Feature", "id": fid, "geometry": geom, "properties": res}


@router.delete("/{tabla}/features/{feature_id}")
async def delete_feature(tabla: str, feature_id: str, updated_by: Optional[str] = Query(None)):
    """
    Soft-delete: marca `deleted_at = NOW()` en lugar de borrar físicamente.
    El registro persiste en la BD para sincronización con dispositivos offline.
    """
    if tabla not in TABLAS_PERMITIDAS:
        raise HTTPException(status_code=400, detail="Tabla no autorizada")

    clean_fid = parse_uuid_or_none(feature_id)
    if not clean_fid:
        raise HTTPException(status_code=400, detail="ID de elemento inválido (debe ser un UUID)")

    clean_updated_by = parse_uuid_or_none(updated_by)

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        es_dueno = await propietario_elemento(conn, tabla, clean_fid, clean_updated_by)
        if not es_dueno:
            raise HTTPException(status_code=403, detail="Ud. no creo este elemento, no tiene permisos de edición")

        sql = f"""
            UPDATE {tabla}
            SET deleted_at = NOW(),
                updated_at = NOW(),
                updated_by = $2::uuid,
                sync_version = {tabla}.sync_version + 1
            WHERE id = $1::uuid AND deleted_at IS NULL
            RETURNING id::text, deleted_at
        """
        row = await conn.fetchrow(sql, clean_fid, clean_updated_by)
        if not row:
            raise HTTPException(status_code=404, detail="Elemento no encontrado o ya eliminado")
        return {
            "ok": True,
            "deleted_id": row['id'],
            "deleted_at": row['deleted_at'].isoformat()
        }


@router.get("/catalogos/estructuras/tipos")
async def get_catalogos_tipos():
    """Retorna los tipos de estructuras disponibles (ej: 1=Formal, 2=Referencia)."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, nombre FROM cat_estructuras_tipo ORDER BY id ASC;"
        )
        return [dict(r) for r in rows]


@router.get("/catalogos/estructuras/categorias")
async def get_catalogos_categorias(
    tipo: Optional[int] = Query(
        default=None,
        description="Filtra categorías por tipo de estructura. 1=Formal, 2=Referencia. "
                    "Si se omite, devuelve todas las categorías."
    )
):
    """
    Retorna las categorías de estructuras.
    Con `tipo` se obtiene solo las categorías del tipo indicado (combo dependiente).
    Sin `tipo` devuelve todas (útil para carga inicial o admin).

    Ejemplo:
      GET /api/capas/catalogos/estructuras/categorias?tipo=1  → solo categorías Formal
      GET /api/capas/catalogos/estructuras/categorias?tipo=2  → solo categorías Referencia
    """
    if tipo is not None and tipo not in TIPOS_ESTRUCTURA_VALIDOS:
        raise HTTPException(
            status_code=422,
            detail=f"Tipo inválido: {tipo!r}. Valores permitidos: {TIPOS_ESTRUCTURA_VALIDOS}"
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        if tipo is not None:
            # Query parametrizada — nunca concatenar tipo en el SQL
            rows = await conn.fetch(
                "SELECT id, nombre, tipo "
                "FROM cat_estructuras_categoria "
                "WHERE tipo = $1 "
                "ORDER BY nombre ASC;",
                tipo
            )
        else:
            rows = await conn.fetch(
                "SELECT id, nombre, tipo "
                "FROM cat_estructuras_categoria "
                "ORDER BY tipo ASC, nombre ASC;"
            )
        return [dict(r) for r in rows]


@router.get("/catalogos/locales/tipos")
async def get_catalogos_locales_tipos():
    """Retorna los tipos de locales disponibles."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, nombre FROM cat_locales_tipo ORDER BY id ASC;"
        )
        return [dict(r) for r in rows]


@router.get("/catalogos/locales/condiciones")
async def get_catalogos_locales_condiciones():
    """Retorna las condiciones de los locales."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, nombre FROM cat_locales_condicion ORDER BY id ASC;"
        )
        return [dict(r) for r in rows]


@router.get("/catalogos/hogares/idiomas")
async def get_catalogos_hogares_idiomas():
    """Retorna el catálogo de idiomas para hogares."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, nombre FROM cat_hogares_idioma ORDER BY id ASC;"
        )
        return [dict(r) for r in rows]


@router.get("/catalogos/hogares/sexo")
async def get_catalogos_hogares_sexo():
    """Retorna el catálogo de sexo."""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, nombre FROM cat_sexo ORDER BY id ASC;"
        )
        return [dict(r) for r in rows]


