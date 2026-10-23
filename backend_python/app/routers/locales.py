from fastapi import APIRouter, HTTPException, status
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime
from app.database import get_db_pool
from app.routers.features import parse_uuid_or_none
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/locales", tags=["Locales"])

class LocalCreateSchema(BaseModel):
    id: Optional[str] = None
    nombre_local: Optional[str] = Field(default=None, max_length=100)
    id_tipo: int
    id_condicion_local: Optional[int] = None
    numero_hogares: Optional[int] = Field(default=None, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=150)

class LocalCreateDirectSchema(BaseModel):
    id: Optional[str] = None
    nivel_id: str
    nombre_local: Optional[str] = Field(default=None, max_length=100)
    id_tipo: int
    id_condicion_local: Optional[int] = None
    numero_hogares: Optional[int] = Field(default=None, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=150)

class LocalPatchSchema(BaseModel):
    nombre_local: Optional[str] = Field(default=None, max_length=100)
    id_tipo: Optional[int] = None
    id_condicion_local: Optional[int] = None
    numero_hogares: Optional[int] = Field(default=None, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=150)


async def _asegurar_nivel_existente(conn, clean_nid: str) -> Dict[str, Any]:
    """
    Asegura que el nivel exista en PostgreSQL.
    Si el nivel fue creado en el cliente móvil y aún no se sincroniza a la base central,
    inserta un registro base para mantener la integridad referencial.
    """
    nivel_row = await conn.fetchrow(
        "SELECT id::text, numero, numero_locales FROM niveles WHERE id = $1::uuid FOR UPDATE",
        clean_nid
    )
    if not nivel_row:
        dummy_est_id = "00000000-0000-0000-0000-000000000001"
        await conn.execute("""
            INSERT INTO estructuras (id, geom, nombre, id_categoria, id_tipo, estado, niveles_cantidad, sync_version)
            VALUES ($1::uuid, ST_SetSRID(ST_MakePoint(-90.6151, 16.1228), 4326), 'Estructura', 1, 1, 'presente', 1, 0)
            ON CONFLICT (id) DO UPDATE SET deleted_at = NULL
        """, dummy_est_id)
        next_num = await conn.fetchval(
            "SELECT COALESCE(MAX(numero), 0) + 1 FROM niveles WHERE estructura_id = $1::uuid",
            dummy_est_id
        ) or 1
        await conn.execute("""
            INSERT INTO niveles (id, estructura_id, numero, numero_locales, updated_at)
            VALUES ($1::uuid, $2::uuid, $3, 1, NOW())
            ON CONFLICT (id) DO NOTHING
        """, clean_nid, dummy_est_id, next_num)
        nivel_row = await conn.fetchrow(
            "SELECT id::text, numero, numero_locales FROM niveles WHERE id = $1::uuid FOR UPDATE",
            clean_nid
        )
    return dict(nivel_row) if nivel_row else {"id": clean_nid, "numero": 1, "numero_locales": 1}


@router.get("/nivel/{nivel_id}")
async def get_locales_by_nivel(nivel_id: str):
    """
    Obtiene la lista de locales pertenecientes a un nivel con detalles de sus catálogos.
    Si el nivel aún no existe en PostgreSQL, devuelve una lista vacía en vez de 404.
    """
    clean_nid = parse_uuid_or_none(nivel_id)
    if not clean_nid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "id_invalido", "message": "El ID de nivel no tiene formato UUID válido"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        nivel_row = await conn.fetchrow(
            "SELECT id::text, numero, numero_locales FROM niveles WHERE id = $1::uuid",
            clean_nid
        )
        if not nivel_row:
            return {
                "nivel_id": clean_nid,
                "numero_nivel": 1,
                "numero_locales_esperados": 1,
                "locales_registrados": 0,
                "locales": []
            }

        sql = """
        SELECT 
            l.id::text,
            l.nivel_id::text,
            l.nombre_local,
            l.numero_hogares,
            l.descripcion,
            l.id_tipo,
            t.nombre AS nombre_tipo,
            l.id_condicion_local,
            c.nombre AS nombre_condicion,
            l.updated_at,
            COUNT(DISTINCT h.id)::int AS hogares_registrados
        FROM locales l
        LEFT JOIN cat_locales_tipo t ON t.id = l.id_tipo
        LEFT JOIN cat_locales_condicion c ON c.id = l.id_condicion_local
        LEFT JOIN hogares h ON h.local_id = l.id
        WHERE l.nivel_id = $1::uuid
        GROUP BY l.id, l.nivel_id, l.nombre_local, l.numero_hogares, l.descripcion, l.id_tipo, t.nombre, l.id_condicion_local, c.nombre, l.updated_at
        ORDER BY l.updated_at ASC, l.id ASC;
        """
        rows = await conn.fetch(sql, clean_nid)
        locales_list = []
        for r in rows:
            item = dict(r)
            if item.get('updated_at'):
                item['updated_at'] = item['updated_at'].isoformat()
            locales_list.append(item)

        return {
            "nivel_id": clean_nid,
            "numero_nivel": nivel_row['numero'],
            "numero_locales_esperados": nivel_row['numero_locales'],
            "locales_registrados": len(locales_list),
            "locales": locales_list
        }


@router.get("")
@router.get("/")
async def list_or_filter_locales(nivel_id: Optional[str] = None):
    """
    Lista todos los locales o filtra por nivel_id si se pasa como query parameter.
    """
    if nivel_id:
        return await get_locales_by_nivel(nivel_id)

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT 
                l.id::text, l.nivel_id::text, l.nombre_local, l.id_tipo, l.id_condicion_local,
                l.numero_hogares, l.descripcion, l.updated_at
            FROM locales l
            ORDER BY l.updated_at ASC
        """)
        locales_list = []
        for r in rows:
            item = dict(r)
            if item.get('updated_at'):
                item['updated_at'] = item['updated_at'].isoformat()
            locales_list.append(item)
        return locales_list


@router.get("/{local_id}")
async def get_local_by_id(local_id: str):
    """
    Obtiene la información de un local específico.
    """
    clean_lid = parse_uuid_or_none(local_id)
    if not clean_lid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
        )
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT 
                l.id::text, l.nivel_id::text, l.nombre_local, l.id_tipo, t.nombre as nombre_tipo,
                l.id_condicion_local, c.nombre as nombre_condicion, l.numero_hogares, l.descripcion, l.updated_at
            FROM locales l
            LEFT JOIN cat_locales_tipo t ON t.id = l.id_tipo
            LEFT JOIN cat_locales_condicion c ON c.id = l.id_condicion_local
            WHERE l.id = $1::uuid
        """, clean_lid)
        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
            )
        res = dict(row)
        if res.get('updated_at'):
            res['updated_at'] = res['updated_at'].isoformat()
        return res


@router.post("/nivel/{nivel_id}", status_code=status.HTTP_201_CREATED)
async def create_local(nivel_id: str, payload: LocalCreateSchema):
    """
    Crea un nuevo local dentro de un nivel.
    Valida el límite máximo de locales esperados según numero_locales del nivel.
    """
    clean_nid = parse_uuid_or_none(nivel_id)
    if not clean_nid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "id_invalido", "message": "El ID de nivel no tiene formato UUID válido"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            nivel_data = await _asegurar_nivel_existente(conn, clean_nid)

            # Verificar que el nivel realmente exista antes de continuar
            # (evita violaciones de FK si el placeholder no pudo crearse)
            nivel_existe = await conn.fetchval(
                "SELECT 1 FROM niveles WHERE id = $1::uuid", clean_nid
            )
            if not nivel_existe:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail={
                        "error": "nivel_no_sincronizado",
                        "message": "El nivel padre aún no ha sido sincronizado con el servidor central."
                    }
                )

            max_locales = nivel_data.get('numero_locales') or 1

            count_actual = await conn.fetchval(
                "SELECT COUNT(*) FROM locales WHERE nivel_id = $1::uuid",
                clean_nid
            ) or 0

            if count_actual >= max_locales:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "local_tope_alcanzado",
                        "message": f"No se pueden crear más locales. El límite para este nivel es {max_locales}.",
                        "data": {
                            "numero_locales_esperados": max_locales,
                            "locales_registrados": count_actual
                        }
                    }
                )

            # Validar existencia de id_tipo
            tipo_exists = await conn.fetchval("SELECT 1 FROM cat_locales_tipo WHERE id = $1", payload.id_tipo)
            if not tipo_exists:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail={"error": "tipo_invalido", "message": f"El id_tipo {payload.id_tipo} no existe en el catálogo."}
                )

            # Validar id_condicion_local si se proporciona
            if payload.id_condicion_local is not None:
                cond_exists = await conn.fetchval("SELECT 1 FROM cat_locales_condicion WHERE id = $1", payload.id_condicion_local)
                if not cond_exists:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail={"error": "condicion_invalida", "message": f"El id_condicion_local {payload.id_condicion_local} no existe."}
                    )

            clean_lid = parse_uuid_or_none(payload.id)
            insert_sql = """
            INSERT INTO locales (id, nivel_id, nombre_local, id_tipo, id_condicion_local, numero_hogares, descripcion, updated_at)
            VALUES (COALESCE($1::uuid, uuid_generate_v4()), $2::uuid, $3, $4, $5, $6, $7, NOW())
            ON CONFLICT (id) DO UPDATE SET
                nombre_local = EXCLUDED.nombre_local,
                id_tipo = EXCLUDED.id_tipo,
                id_condicion_local = EXCLUDED.id_condicion_local,
                numero_hogares = EXCLUDED.numero_hogares,
                descripcion = EXCLUDED.descripcion,
                updated_at = NOW()
            RETURNING id::text, nivel_id::text, nombre_local, id_tipo, id_condicion_local, numero_hogares, descripcion, updated_at;
            """
            row = await conn.fetchrow(
                insert_sql,
                clean_lid,
                clean_nid,
                payload.nombre_local,
                payload.id_tipo,
                payload.id_condicion_local,
                payload.numero_hogares,
                payload.descripcion
            )
            res = dict(row)
            if res.get('updated_at'):
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.post("", status_code=status.HTTP_201_CREATED)
@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_local_direct(payload: LocalCreateDirectSchema):
    """
    Endpoint directo para crear local recibiendo nivel_id en el cuerpo de la petición.
    """
    schema = LocalCreateSchema(
        id=payload.id,
        nombre_local=payload.nombre_local,
        id_tipo=payload.id_tipo,
        id_condicion_local=payload.id_condicion_local,
        numero_hogares=payload.numero_hogares,
        descripcion=payload.descripcion
    )
    return await create_local(payload.nivel_id, schema)


@router.patch("/{local_id}")
async def patch_local(local_id: str, payload: LocalPatchSchema):
    """
    Edita la información de un local.
    """
    clean_lid = parse_uuid_or_none(local_id)
    if not clean_lid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            local_row = await conn.fetchrow("SELECT id::text FROM locales WHERE id = $1::uuid FOR UPDATE", clean_lid)
            if not local_row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
                )

            updates = []
            args = [clean_lid]
            idx = 2

            if payload.nombre_local is not None:
                updates.append(f"nombre_local = ${idx}")
                args.append(payload.nombre_local)
                idx += 1

            if payload.id_tipo is not None:
                tipo_exists = await conn.fetchval("SELECT 1 FROM cat_locales_tipo WHERE id = $1", payload.id_tipo)
                if not tipo_exists:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail={"error": "tipo_invalido", "message": f"El id_tipo {payload.id_tipo} no existe."}
                    )
                updates.append(f"id_tipo = ${idx}")
                args.append(payload.id_tipo)
                idx += 1

            if payload.id_condicion_local is not None:
                cond_exists = await conn.fetchval("SELECT 1 FROM cat_locales_condicion WHERE id = $1", payload.id_condicion_local)
                if not cond_exists:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail={"error": "condicion_invalida", "message": f"El id_condicion_local {payload.id_condicion_local} no existe."}
                    )
                updates.append(f"id_condicion_local = ${idx}")
                args.append(payload.id_condicion_local)
                idx += 1

            if payload.numero_hogares is not None:
                updates.append(f"numero_hogares = ${idx}")
                args.append(payload.numero_hogares)
                idx += 1

            if "descripcion" in payload.model_fields_set:
                desc_val = payload.descripcion.strip() if payload.descripcion else None
                updates.append(f"descripcion = ${idx}")
                args.append(desc_val)
                idx += 1

            if not updates:
                raise HTTPException(status_code=400, detail="No se enviaron campos a actualizar")

            updates.append("updated_at = NOW()")

            update_sql = f"""
            UPDATE locales
            SET {", ".join(updates)}
            WHERE id = $1::uuid
            RETURNING id::text, nivel_id::text, nombre_local, id_tipo, id_condicion_local, numero_hogares, descripcion, updated_at;
            """
            row = await conn.fetchrow(update_sql, *args)
            res = dict(row)
            if res.get('updated_at'):
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.delete("/{local_id}", status_code=status.HTTP_200_OK)
async def delete_local(local_id: str):
    """
    Elimina un local y sus hogares asociados en cascada.
    """
    clean_lid = parse_uuid_or_none(local_id)
    if not clean_lid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                "DELETE FROM locales WHERE id = $1::uuid RETURNING id::text, nivel_id::text;",
                clean_lid
            )
            if not row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
                )
            return {"ok": True, "deleted_id": row['id'], "nivel_id": row['nivel_id']}
