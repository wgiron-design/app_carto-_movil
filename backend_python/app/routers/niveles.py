from fastapi import APIRouter, HTTPException, status
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime
from app.database import get_db_pool
from app.routers.features import parse_uuid_or_none
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/niveles", tags=["Niveles"])
estructuras_niveles_router = APIRouter(prefix="/api/estructuras", tags=["Niveles"])

class NivelCreateSchema(BaseModel):
    id: Optional[str] = None
    numero: Optional[int] = None
    numero_locales: int = Field(default=1, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=50)

class NivelCreateDirectSchema(BaseModel):
    id: Optional[str] = None
    estructura_id: str
    numero: Optional[int] = None
    numero_locales: int = Field(default=1, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=50)

class NivelPatchSchema(BaseModel):
    numero_locales: Optional[int] = Field(default=None, ge=1)
    descripcion: Optional[str] = Field(default=None, max_length=50)

class ConfirmDeleteSchema(BaseModel):
    numero_locales_nuevo: int = Field(..., ge=1)


async def _asegurar_estructura_existente(conn, clean_eid: str) -> Dict[str, Any]:
    """
    Verifica que la estructura exista en PostgreSQL.
    Si fue creada recientemente en el cliente móvil y aún no se ha sincronizado,
    inserta un registro base para garantizar la integridad referencial (FK) y
    evitar errores 404 que impidan el registro de niveles.
    Los IDs de catálogo se consultan dinámicamente para evitar violaciones de FK.
    """
    est_row = await conn.fetchrow(
        "SELECT id::text, nombre, niveles_cantidad FROM estructuras WHERE id = $1::uuid AND deleted_at IS NULL FOR UPDATE",
        clean_eid
    )
    if not est_row:
        # Obtener el primer id_tipo e id_categoria disponibles en los catálogos
        # para evitar violaciones de FK con valores hardcodeados
        cat_tipo_id = await conn.fetchval(
            "SELECT id FROM cat_estructuras_tipo ORDER BY id ASC LIMIT 1"
        )
        cat_cat_id = await conn.fetchval(
            "SELECT id FROM cat_estructuras_categoria ORDER BY id ASC LIMIT 1"
        )
        if cat_tipo_id is None or cat_cat_id is None:
            # Si los catálogos están vacíos, no podemos insertar la estructura
            # Se retorna metadata mínima para que el flujo continúe con fallback SQLite
            logger.warning(
                f"No se pudo registrar estructura {clean_eid} en PostgreSQL: catálogos vacíos. "
                "El nivel se guardará localmente."
            )
            return {"id": clean_eid, "nombre": "Estructura", "niveles_cantidad": 10}
        await conn.execute("""
            INSERT INTO estructuras (
                id, geom, nombre, id_categoria, id_tipo, estado, niveles_cantidad, sync_version
            )
            VALUES (
                $1::uuid,
                ST_SetSRID(ST_MakePoint(-90.5, 14.6), 4326),
                'Estructura',
                $2, $3, 'presente', 10, 0
            )
            ON CONFLICT (id) DO UPDATE SET deleted_at = NULL
        """, clean_eid, cat_cat_id, cat_tipo_id)
        est_row = await conn.fetchrow(
            "SELECT id::text, nombre, niveles_cantidad FROM estructuras WHERE id = $1::uuid FOR UPDATE",
            clean_eid
        )
    return dict(est_row) if est_row else {"id": clean_eid, "nombre": "Estructura", "niveles_cantidad": 10}


@router.get("/estructura/{estructura_id}")
async def get_niveles_by_estructura(estructura_id: str):
    """
    Obtiene la lista de niveles de una estructura con sus métricas agregadas
    y la información del tope permitido (niveles_cantidad).
    Si la estructura no existe aún en PostgreSQL (creada offline), devuelve
    una lista vacía limpia en lugar de 404 para no bloquear al cliente.
    """
    clean_eid = parse_uuid_or_none(estructura_id)
    if not clean_eid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "id_invalido", "message": "El ID de la estructura no tiene formato UUID válido"}
        )

    pool = await get_db_pool()
    for attempt in range(2):
        try:
            async with pool.acquire() as conn:
                # 1. Obtener datos de la estructura
                est_row = await conn.fetchrow(
                    "SELECT id::text, nombre, niveles_cantidad FROM estructuras WHERE id = $1::uuid AND deleted_at IS NULL",
                    clean_eid
                )
                if not est_row:
                    return {
                        "estructura_id": clean_eid,
                        "nombre_estructura": "Estructura",
                        "niveles_cantidad": 10,
                        "niveles_registrados": 0,
                        "niveles": []
                    }
                
                niveles_cantidad = est_row['niveles_cantidad'] or 1

                # 2. Consultar niveles con agregados de completitud
                sql = """
                SELECT 
                    n.id::text,
                    n.numero,
                    n.numero_locales,
                    n.descripcion,
                    n.updated_at,
                    COUNT(DISTINCT l.id)::int AS locales_registrados,
                    COUNT(DISTINCT h.id)::int AS hogares_registrados,
                    COALESCE(SUM(h.total_habitantes), 0)::int AS personas_registradas
                FROM niveles n
                LEFT JOIN locales l ON l.nivel_id = n.id
                LEFT JOIN hogares h ON h.local_id = l.id
                WHERE n.estructura_id = $1::uuid
                GROUP BY n.id, n.numero, n.numero_locales, n.descripcion, n.updated_at
                ORDER BY n.numero ASC;
                """
                rows = await conn.fetch(sql, clean_eid)
                
                niveles_list = []
                for r in rows:
                    item = dict(r)
                    if item.get('updated_at'):
                        item['updated_at'] = item['updated_at'].isoformat()
                    niveles_list.append(item)

                return {
                    "estructura_id": clean_eid,
                    "nombre_estructura": est_row['nombre'],
                    "niveles_cantidad": niveles_cantidad,
                    "niveles_registrados": len(niveles_list),
                    "niveles": niveles_list
                }
        except Exception as e:
            if attempt == 1:
                raise
            logger.warning(f"Reintentando consulta get_niveles_by_estructura por reconexión pool: {e}")


@router.get("")
@router.get("/")
async def list_or_filter_niveles(estructura_id: Optional[str] = None):
    """
    Lista todos los niveles o filtra por estructura_id si se provee como query param.
    """
    if estructura_id:
        return await get_niveles_by_estructura(estructura_id)

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT 
                n.id::text, n.estructura_id::text, n.numero, n.numero_locales, n.descripcion, n.updated_at,
                COUNT(DISTINCT l.id)::int AS locales_registrados
            FROM niveles n
            LEFT JOIN locales l ON l.nivel_id = n.id
            GROUP BY n.id, n.estructura_id, n.numero, n.numero_locales, n.descripcion, n.updated_at
            ORDER BY n.estructura_id, n.numero ASC
        """)
        niveles_list = []
        for r in rows:
            item = dict(r)
            if item.get('updated_at'):
                item['updated_at'] = item['updated_at'].isoformat()
            niveles_list.append(item)
        return niveles_list


@router.get("/{nivel_id}")
async def get_nivel_by_id(nivel_id: str):
    """
    Obtiene la información detallada de un nivel por su ID.
    """
    clean_nid = parse_uuid_or_none(nivel_id)
    if not clean_nid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
        )
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT 
                n.id::text, n.estructura_id::text, n.numero, n.numero_locales, n.descripcion, n.updated_at,
                COUNT(DISTINCT l.id)::int AS locales_registrados
            FROM niveles n
            LEFT JOIN locales l ON l.nivel_id = n.id
            WHERE n.id = $1::uuid
            GROUP BY n.id, n.estructura_id, n.numero, n.numero_locales, n.descripcion, n.updated_at
        """, clean_nid)
        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
            )
        res = dict(row)
        if res.get('updated_at'):
            res['updated_at'] = res['updated_at'].isoformat()
        return res


@router.post("/estructura/{estructura_id}", status_code=status.HTTP_201_CREATED)
async def create_nivel(estructura_id: str, payload: NivelCreateSchema):
    """
    Crea un nuevo nivel asignando automáticamente el consecutivo siguiente.
    Valida que no se supere niveles_cantidad.
    Garantiza que si la estructura no existe aún en PostgreSQL se inserte de forma segura.
    """
    clean_eid = parse_uuid_or_none(estructura_id)
    if not clean_eid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": "id_invalido", "message": "El ID de la estructura no tiene formato UUID válido"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            est_data = await _asegurar_estructura_existente(conn, clean_eid)
            niveles_cantidad = est_data.get('niveles_cantidad') or 10
            
            # Contar niveles existentes
            count_row = await conn.fetchval(
                "SELECT COUNT(*) FROM niveles WHERE estructura_id = $1::uuid",
                clean_eid
            )
            niveles_registrados = count_row or 0

            if niveles_registrados >= niveles_cantidad:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "nivel_tope_alcanzado",
                        "message": f"No se pueden crear más niveles. El límite configurado para esta estructura es de {niveles_cantidad}.",
                        "data": {
                            "niveles_cantidad": niveles_cantidad,
                            "niveles_registrados": niveles_registrados
                        }
                    }
                )

            # Autoasociar consecutivo siguiente o usar el indicado
            if payload.numero is not None and payload.numero > 0:
                siguiente_numero = payload.numero
            else:
                max_num = await conn.fetchval(
                    "SELECT COALESCE(MAX(numero), 0) FROM niveles WHERE estructura_id = $1::uuid",
                    clean_eid
                )
                siguiente_numero = max_num + 1

            # Insertar nuevo nivel
            clean_nid = parse_uuid_or_none(payload.id)
            desc_val = payload.descripcion[:50] if payload.descripcion else None
            insert_sql = """
            INSERT INTO niveles (id, estructura_id, numero, numero_locales, descripcion, updated_at)
            VALUES (COALESCE($1::uuid, uuid_generate_v4()), $2::uuid, $3, $4, $5, NOW())
            ON CONFLICT (id) DO UPDATE SET
                numero = EXCLUDED.numero,
                numero_locales = EXCLUDED.numero_locales,
                descripcion = EXCLUDED.descripcion,
                updated_at = NOW()
            RETURNING id::text, estructura_id::text, numero, numero_locales, descripcion, updated_at;
            """
            row = await conn.fetchrow(insert_sql, clean_nid, clean_eid, siguiente_numero, payload.numero_locales, desc_val)
            res = dict(row)
            if res.get('updated_at'):
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.post("", status_code=status.HTTP_201_CREATED)
@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_nivel_direct(payload: NivelCreateDirectSchema):
    """
    Endpoint directo para crear niveles enviando estructura_id en el payload.
    Evita errores 404 si el cliente envía POST a /api/niveles.
    """
    schema = NivelCreateSchema(
        id=payload.id,
        numero=payload.numero,
        numero_locales=payload.numero_locales,
        descripcion=payload.descripcion
    )
    return await create_nivel(payload.estructura_id, schema)


@router.patch("/{nivel_id}")
async def patch_nivel(nivel_id: str, payload: NivelPatchSchema):
    """
    Edita la información de un nivel (numero_locales, descripcion).
    Si se intenta reducir numero_locales por debajo de los locales ya registrados con datos,
    rechaza con un error 409 estructurado detallando la cantidad de datos que se perderían.
    """
    clean_nid = parse_uuid_or_none(nivel_id)
    if not clean_nid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            # 1. Obtener nivel actual
            nivel_row = await conn.fetchrow(
                "SELECT id::text, estructura_id::text, numero, numero_locales, descripcion FROM niveles WHERE id = $1::uuid FOR UPDATE",
                clean_nid
            )
            if not nivel_row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
                )

            numero_locales_actual = nivel_row['numero_locales']
            nuevo_numero_locales = payload.numero_locales if payload.numero_locales is not None else numero_locales_actual
            nueva_descripcion = payload.descripcion if payload.descripcion is not None else nivel_row['descripcion']
            if nueva_descripcion:
                nueva_descripcion = nueva_descripcion[:50]

            # 2. Si se reduce numero_locales, validar pérdida de datos
            if nuevo_numero_locales < numero_locales_actual:
                locales_existentes = await conn.fetch(
                    "SELECT id::text FROM locales WHERE nivel_id = $1::uuid ORDER BY updated_at ASC, id ASC",
                    clean_nid
                )
                
                locales_count = len(locales_existentes)
                if locales_count > nuevo_numero_locales:
                    locales_excedentes_ids = [l['id'] for l in locales_existentes[nuevo_numero_locales:]]
                    
                    metrics = await conn.fetchrow(
                        """
                        SELECT 
                            COUNT(DISTINCT h.id)::int as hogares_afectados,
                            COALESCE(SUM(h.total_habitantes), 0)::int as personas_afectadas
                        FROM hogares h
                        WHERE h.local_id = ANY($1::uuid[])
                        """,
                        locales_excedentes_ids
                    )
                    
                    locales_afectados = len(locales_excedentes_ids)
                    hogares_afectados = metrics['hogares_afectados'] if metrics else 0
                    personas_afectadas = metrics['personas_afectadas'] if metrics else 0

                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail={
                            "error": "perdida_de_datos_local",
                            "message": "Reducir el número de locales causaría la pérdida de locales y hogares registrados.",
                            "data": {
                                "nivel_id": nivel_id,
                                "numero_locales_actual": numero_locales_actual,
                                "numero_locales_solicitado": nuevo_numero_locales,
                                "locales_afectados": locales_afectados,
                                "hogares_afectados": hogares_afectados,
                                "personas_afectadas": personas_afectadas
                            }
                        }
                    )

            # 3. Aplicar actualización si no hay conflicto
            update_sql = """
            UPDATE niveles
            SET numero_locales = $2,
                descripcion = $3,
                updated_at = NOW(),
                sync_version = sync_version + 1
            WHERE id = $1::uuid
            RETURNING id::text, estructura_id::text, numero, numero_locales, descripcion, updated_at;
            """
            row = await conn.fetchrow(update_sql, clean_nid, nuevo_numero_locales, nueva_descripcion)
            res = dict(row)
            if res.get('updated_at'):
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.delete("/{nivel_id}/locales-excedentes")
async def delete_locales_excedentes(nivel_id: str, payload: ConfirmDeleteSchema):
    """
    Endpoint de confirmación explícita para reducir numero_locales y eliminar en cascada
    los locales y hogares sobrantes.
    """
    clean_nid = parse_uuid_or_none(nivel_id)
    if not clean_nid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            nivel_row = await conn.fetchrow(
                "SELECT id::text, numero_locales FROM niveles WHERE id = $1::uuid FOR UPDATE",
                clean_nid
            )
            if not nivel_row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "nivel_no_encontrado", "message": "El nivel especificado no existe"}
                )

            nuevo_numero = payload.numero_locales_nuevo

            locales_existentes = await conn.fetch(
                "SELECT id::text FROM locales WHERE nivel_id = $1::uuid ORDER BY updated_at ASC, id ASC",
                clean_nid
            )
            
            if len(locales_existentes) > nuevo_numero:
                locales_eliminar = [l['id'] for l in locales_existentes[nuevo_numero:]]
                await conn.execute("DELETE FROM hogares WHERE local_id = ANY($1::uuid[])", locales_eliminar)
                await conn.execute("DELETE FROM locales WHERE id = ANY($1::uuid[])", locales_eliminar)

            update_sql = """
            UPDATE niveles
            SET numero_locales = $2,
                updated_at = NOW(),
                sync_version = sync_version + 1
            WHERE id = $1::uuid
            RETURNING id::text, estructura_id::text, numero, numero_locales, descripcion, updated_at;
            """
            row = await conn.fetchrow(update_sql, clean_nid, nuevo_numero)
            res = dict(row)
            if res.get('updated_at'):
                res['updated_at'] = res['updated_at'].isoformat()
            return res


# ── Rutas anidadas bajo /api/estructuras/{estructura_id}/niveles ─────────────
@estructuras_niveles_router.get("/{estructura_id}/niveles")
async def get_niveles_de_estructura_alias(estructura_id: str):
    return await get_niveles_by_estructura(estructura_id)

@estructuras_niveles_router.post("/{estructura_id}/niveles", status_code=status.HTTP_201_CREATED)
async def create_nivel_de_estructura_alias(estructura_id: str, payload: NivelCreateSchema):
    return await create_nivel(estructura_id, payload)
