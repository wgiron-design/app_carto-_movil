from fastapi import APIRouter, HTTPException, status
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime
from app.database import get_db_pool
from app.routers.features import parse_uuid_or_none
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/hogares", tags=["Hogares"])

class HogarCreateSchema(BaseModel):
    jefe_familia: Optional[str] = Field(default=None, max_length=150)
    id_sexo: Optional[int] = None
    id_idioma: Optional[int] = None
    direccion: Optional[str] = Field(default=None, max_length=200)
    total_habitantes: Optional[int] = Field(default=0, ge=0)
    personas_0_5: Optional[int] = Field(default=0, ge=0)
    personas_6_11: Optional[int] = Field(default=0, ge=0)
    personas_12_17: Optional[int] = Field(default=0, ge=0)
    personas_18_23: Optional[int] = Field(default=0, ge=0)
    personas_24_34: Optional[int] = Field(default=0, ge=0)
    personas_35_44: Optional[int] = Field(default=0, ge=0)
    personas_45_59: Optional[int] = Field(default=0, ge=0)
    personas_60_69: Optional[int] = Field(default=0, ge=0)
    personas_70_79: Optional[int] = Field(default=0, ge=0)
    personas_80_mas: Optional[int] = Field(default=0, ge=0)
    personas_no_edad: Optional[int] = Field(default=0, ge=0)

class HogarPatchSchema(BaseModel):
    jefe_familia: Optional[str] = Field(default=None, max_length=150)
    id_sexo: Optional[int] = None
    id_idioma: Optional[int] = None
    direccion: Optional[str] = Field(default=None, max_length=200)
    total_habitantes: Optional[int] = Field(default=None, ge=0)
    personas_0_5: Optional[int] = Field(default=None, ge=0)
    personas_6_11: Optional[int] = Field(default=None, ge=0)
    personas_12_17: Optional[int] = Field(default=None, ge=0)
    personas_18_23: Optional[int] = Field(default=None, ge=0)
    personas_24_34: Optional[int] = Field(default=None, ge=0)
    personas_35_44: Optional[int] = Field(default=None, ge=0)
    personas_45_59: Optional[int] = Field(default=None, ge=0)
    personas_60_69: Optional[int] = Field(default=None, ge=0)
    personas_70_79: Optional[int] = Field(default=None, ge=0)
    personas_80_mas: Optional[int] = Field(default=None, ge=0)
    personas_no_edad: Optional[int] = Field(default=None, ge=0)


async def _asegurar_local_existente(conn, clean_lid: str) -> Optional[Dict[str, Any]]:
    """
    Asegura que el local exista en PostgreSQL.
    Si el local fue creado en el cliente móvil y aún no se sincroniza a la base central,
    inserta un registro base para mantener la integridad referencial.
    """
    local_row = await conn.fetchrow(
        "SELECT id::text, numero_hogares FROM locales WHERE id = $1::uuid FOR UPDATE",
        clean_lid
    )
    if not local_row:
        # Obtener un nivel existente para asociar el local
        niv_id = await conn.fetchval("SELECT id::text FROM niveles LIMIT 1")
        if not niv_id:
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
            niv_id = "00000000-0000-0000-0000-000000000002"
            await conn.execute("""
                INSERT INTO niveles (id, estructura_id, numero, numero_locales, updated_at)
                VALUES ($1::uuid, $2::uuid, $3, 1, NOW())
                ON CONFLICT (id) DO NOTHING
            """, niv_id, dummy_est_id, next_num)

        await conn.execute("""
            INSERT INTO locales (id, nivel_id, nombre_local, id_tipo, numero_hogares, updated_at)
            VALUES ($1::uuid, $2::uuid, 'Local', 1, 1, NOW())
            ON CONFLICT (id) DO NOTHING
        """, clean_lid, niv_id)
        local_row = await conn.fetchrow(
            "SELECT id::text, numero_hogares FROM locales WHERE id = $1::uuid FOR UPDATE",
            clean_lid
        )
    return dict(local_row) if local_row else None


@router.get("/local/{local_id}")
async def get_hogares_by_local(local_id: str):
    """
    Obtiene la lista de hogares de un local con los nombres de sus catálogos asociados.
    """
    clean_lid = parse_uuid_or_none(local_id)
    if not clean_lid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        local_row = await conn.fetchrow(
            "SELECT id::text, nombre_local, numero_hogares, id_tipo, id_condicion_local FROM locales WHERE id = $1::uuid",
            clean_lid
        )
        if not local_row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"error": "local_no_encontrado", "message": "El local especificado no existe"}
            )

        sql = """
        SELECT 
            h.id::text,
            h.local_id::text,
            h.jefe_familia,
            h.id_sexo,
            s.nombre AS nombre_sexo,
            h.id_idioma,
            i.nombre AS nombre_idioma,
            h.direccion,
            h.total_habitantes,
            h.personas_0_5,
            h.personas_6_11,
            h.personas_12_17,
            h.personas_18_23,
            h.personas_24_34,
            h.personas_35_44,
            h.personas_45_59,
            h.personas_60_69,
            h.personas_70_79,
            h.personas_80_mas,
            h.personas_no_edad,
            h.updated_at
        FROM hogares h
        LEFT JOIN cat_sexo s ON s.id = h.id_sexo
        LEFT JOIN cat_hogares_idioma i ON i.id = h.id_idioma
        WHERE h.local_id = $1::uuid
        ORDER BY h.updated_at ASC, h.id ASC;
        """
        rows = await conn.fetch(sql, clean_lid)
        hogares_list = []
        for r in rows:
            item = dict(r)
            if item['updated_at']:
                item['updated_at'] = item['updated_at'].isoformat()
            hogares_list.append(item)

        return {
            "local_id": clean_lid,
            "nombre_local": local_row['nombre_local'],
            "numero_hogares_esperados": local_row['numero_hogares'],
            "id_tipo": local_row['id_tipo'],
            "id_tipo_local": local_row['id_tipo'],
            "id_condicion_local": local_row['id_condicion_local'],
            "hogares_registrados": len(hogares_list),
            "hogares": hogares_list
        }


@router.post("/local/{local_id}", status_code=status.HTTP_201_CREATED)
async def create_hogar(local_id: str, payload: HogarCreateSchema):
    """
    Crea un nuevo hogar dentro de un local.
    Valida el límite máximo de hogares esperados según numero_hogares del local.
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
            local_row = await _asegurar_local_existente(conn, clean_lid)
            if not local_row:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail={
                        "error": "local_no_sincronizado",
                        "message": "El local padre aún no ha sido sincronizado con el servidor central."
                    }
                )

            max_hogares = local_row['numero_hogares']
            if max_hogares is not None:
                count_actual = await conn.fetchval(
                    "SELECT COUNT(*) FROM hogares WHERE local_id = $1::uuid",
                    clean_lid
                ) or 0

                if count_actual >= max_hogares:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail={
                            "error": "hogar_tope_alcanzado",
                            "message": f"No se pueden crear más hogares. El límite para este local es {max_hogares}.",
                            "data": {
                                "numero_hogares_esperados": max_hogares,
                                "hogares_registrados": count_actual
                            }
                        }
                    )

            if payload.id_sexo is not None:
                sexo_exists = await conn.fetchval("SELECT 1 FROM cat_sexo WHERE id = $1", payload.id_sexo)
                if not sexo_exists:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail={"error": "sexo_invalido", "message": f"El id_sexo {payload.id_sexo} no existe en el catálogo."}
                    )

            if payload.id_idioma is not None:
                idioma_exists = await conn.fetchval("SELECT 1 FROM cat_hogares_idioma WHERE id = $1", payload.id_idioma)
                if not idioma_exists:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail={"error": "idioma_invalido", "message": f"El id_idioma {payload.id_idioma} no existe en el catálogo."}
                    )

            insert_sql = """
            INSERT INTO hogares (
                local_id, jefe_familia, id_sexo, id_idioma, direccion, total_habitantes,
                personas_0_5, personas_6_11, personas_12_17, personas_18_23,
                personas_24_34, personas_35_44, personas_45_59, personas_60_69,
                personas_70_79, personas_80_mas, personas_no_edad, updated_at
            )
            VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, NOW())
            RETURNING id::text, local_id::text, jefe_familia, id_sexo, id_idioma, direccion, total_habitantes,
                      personas_0_5, personas_6_11, personas_12_17, personas_18_23,
                      personas_24_34, personas_35_44, personas_45_59, personas_60_69,
                      personas_70_79, personas_80_mas, personas_no_edad, updated_at;
            """
            row = await conn.fetchrow(
                insert_sql,
                clean_lid, payload.jefe_familia, payload.id_sexo, payload.id_idioma, payload.direccion,
                payload.total_habitantes or 0, payload.personas_0_5 or 0, payload.personas_6_11 or 0,
                payload.personas_12_17 or 0, payload.personas_18_23 or 0, payload.personas_24_34 or 0,
                payload.personas_35_44 or 0, payload.personas_45_59 or 0, payload.personas_60_69 or 0,
                payload.personas_70_79 or 0, payload.personas_80_mas or 0, payload.personas_no_edad or 0
            )
            res = dict(row)
            if res['updated_at']:
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.patch("/{hogar_id}")
async def patch_hogar(hogar_id: str, payload: HogarPatchSchema):
    """
    Edita la información de un hogar.
    """
    clean_hid = parse_uuid_or_none(hogar_id)
    if not clean_hid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "hogar_no_encontrado", "message": "El hogar especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            hogar_row = await conn.fetchrow(
                "SELECT id::text FROM hogares WHERE id = $1::uuid FOR UPDATE",
                clean_hid
            )
            if not hogar_row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "hogar_no_encontrado", "message": "El hogar especificado no existe"}
                )

            updates = []
            args = [clean_hid]
            idx = 2

            fields = [
                ("jefe_familia", payload.jefe_familia),
                ("id_sexo", payload.id_sexo),
                ("id_idioma", payload.id_idioma),
                ("direccion", payload.direccion),
                ("total_habitantes", payload.total_habitantes),
                ("personas_0_5", payload.personas_0_5),
                ("personas_6_11", payload.personas_6_11),
                ("personas_12_17", payload.personas_12_17),
                ("personas_18_23", payload.personas_18_23),
                ("personas_24_34", payload.personas_24_34),
                ("personas_35_44", payload.personas_35_44),
                ("personas_45_59", payload.personas_45_59),
                ("personas_60_69", payload.personas_60_69),
                ("personas_70_79", payload.personas_70_79),
                ("personas_80_mas", payload.personas_80_mas),
                ("personas_no_edad", payload.personas_no_edad),
            ]

            for field_name, field_val in fields:
                if field_val is not None:
                    if field_name == "id_sexo":
                        sexo_exists = await conn.fetchval("SELECT 1 FROM cat_sexo WHERE id = $1", field_val)
                        if not sexo_exists:
                            raise HTTPException(
                                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail={"error": "sexo_invalido", "message": f"El id_sexo {field_val} no existe."}
                            )
                    elif field_name == "id_idioma":
                        idioma_exists = await conn.fetchval("SELECT 1 FROM cat_hogares_idioma WHERE id = $1", field_val)
                        if not idioma_exists:
                            raise HTTPException(
                                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail={"error": "idioma_invalido", "message": f"El id_idioma {field_val} no existe."}
                            )
                    updates.append(f"{field_name} = ${idx}")
                    args.append(field_val)
                    idx += 1

            if not updates:
                raise HTTPException(status_code=400, detail="No se enviaron campos a actualizar")

            updates.append("updated_at = NOW()")

            update_sql = f"""
            UPDATE hogares
            SET {", ".join(updates)}
            WHERE id = $1::uuid
            RETURNING id::text, local_id::text, jefe_familia, id_sexo, id_idioma, direccion, total_habitantes,
                      personas_0_5, personas_6_11, personas_12_17, personas_18_23,
                      personas_24_34, personas_35_44, personas_45_59, personas_60_69,
                      personas_70_79, personas_80_mas, personas_no_edad, updated_at;
            """
            row = await conn.fetchrow(update_sql, *args)
            res = dict(row)
            if res['updated_at']:
                res['updated_at'] = res['updated_at'].isoformat()
            return res


@router.delete("/{hogar_id}", status_code=status.HTTP_200_OK)
async def delete_hogar(hogar_id: str):
    """
    Elimina un hogar.
    """
    clean_hid = parse_uuid_or_none(hogar_id)
    if not clean_hid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "hogar_no_encontrado", "message": "El hogar especificado no existe"}
        )

    pool = await get_db_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                "DELETE FROM hogares WHERE id = $1::uuid RETURNING id::text, local_id::text;",
                clean_hid
            )
            if not row:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail={"error": "hogar_no_encontrado", "message": "El hogar especificado no existe"}
                )
            return {"ok": True, "deleted_id": row['id'], "local_id": row['local_id']}
