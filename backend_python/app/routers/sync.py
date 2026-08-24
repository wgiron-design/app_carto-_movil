import json
import logging
from fastapi import APIRouter, HTTPException
from typing import Any, Dict, List, Optional
from app.database import get_db_pool
from app.schemas.feature import SyncBatchPayload, SyncResult, SyncedItem
from app.routers.features import parse_uuid_or_none, parse_int_or_none

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api/sync", tags=["Sincronizacion Offline"])


@router.post("", response_model=SyncResult)
async def batch_sync(payload: SyncBatchPayload):
    """
    Sincronización por lotes (offline-first).
    Acepta puntos, líneas, polígonos, niveles, locales y hogares pendientes del dispositivo.
    Incluye user_id y device_id para auditoría con validación defensiva de FK.
    Retorna los id, sync_version y updated_at de cada registro sincronizado.
    """
    pool = await get_db_pool()

    user_id_raw = parse_uuid_or_none(payload.user_id)
    device_id = payload.device_id or None

    result: Dict[str, List[SyncedItem]] = {
        "puntos": [],
        "lineas": [],
        "poligonos": [],
        "niveles": [],
        "locales": [],
        "hogares": [],
    }

    async with pool.acquire() as conn:
        # Validar si user_id existe realmente en la tabla users
        valid_user_id = None
        if user_id_raw:
            try:
                user_row = await conn.fetchval("SELECT id FROM users WHERE id = $1 AND is_active = true", user_id_raw)
                if user_row:
                    valid_user_id = user_row
            except Exception as e:
                logger.warning(f"[Sync] Error validando user_id {user_id_raw}: {e}")

        async with conn.transaction():
            # ── 1. Sync Puntos (estructuras) ─────────────────────────────────
            for p in payload.puntos:
                fid = parse_uuid_or_none(p.id)
                geom = p.geometry
                props = p.properties
                if not geom:
                    continue
                geom_json = json.dumps(geom)
                id_cat = parse_int_or_none(props.get("id_categoria")) or 1
                id_tip = parse_int_or_none(props.get("id_tipo")) or 1

                row = await conn.fetchrow("""
                    INSERT INTO estructuras (
                        id, geom, nombre, notas, id_categoria, id_tipo,
                        estado, niveles_cantidad,
                        created_by, updated_by, device_id, sync_version,
                        sync_dirty, updated_at
                    )
                    VALUES (
                        COALESCE($1::uuid, uuid_generate_v4()),
                        ST_GeomFromGeoJSON($2), $3, $4, $5, $6, $7, $8,
                        $9::uuid, $9::uuid, $10, 0, false, NOW()
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        geom = EXCLUDED.geom,
                        nombre = EXCLUDED.nombre,
                        notas = EXCLUDED.notas,
                        id_categoria = EXCLUDED.id_categoria,
                        id_tipo = EXCLUDED.id_tipo,
                        estado = EXCLUDED.estado,
                        niveles_cantidad = EXCLUDED.niveles_cantidad,
                        updated_by = $9::uuid,
                        device_id = $10,
                        sync_version = estructuras.sync_version + 1,
                        sync_dirty = false,
                        updated_at = NOW(),
                        deleted_at = NULL
                    RETURNING id::text, sync_version, updated_at
                """,
                fid, geom_json,
                props.get("nombre"), props.get("notas"), id_cat, id_tip,
                props.get("estado"), props.get("niveles_cantidad", 1),
                valid_user_id, device_id)

                if row:
                    result["puntos"].append(SyncedItem(
                        id=row['id'],
                        sync_version=row['sync_version'],
                        updated_at=row['updated_at'],
                    ))

            # ── 2. Sync Líneas (caminos) ─────────────────────────────────────
            for l in payload.lineas:
                fid = parse_uuid_or_none(l.id)
                geom = l.geometry
                props = l.properties
                if not geom:
                    continue
                geom_json = json.dumps(geom)
                row = await conn.fetchrow("""
                    INSERT INTO caminos (
                        id, geom, nombre, tipo, notas,
                        created_by, updated_by, device_id, sync_version,
                        sync_dirty, updated_at
                    )
                    VALUES (
                        COALESCE($1::uuid, uuid_generate_v4()),
                        ST_GeomFromGeoJSON($2), $3, $4, $5,
                        $6::uuid, $6::uuid, $7, 0, false, NOW()
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        geom = EXCLUDED.geom,
                        nombre = EXCLUDED.nombre,
                        tipo = EXCLUDED.tipo,
                        notas = EXCLUDED.notas,
                        updated_by = $6::uuid,
                        device_id = $7,
                        sync_version = caminos.sync_version + 1,
                        sync_dirty = false,
                        updated_at = NOW(),
                        deleted_at = NULL
                    RETURNING id::text, sync_version, updated_at
                """,
                fid, geom_json,
                props.get("nombre"), props.get("tipo"), props.get("notas"),
                valid_user_id, device_id)

                if row:
                    result["lineas"].append(SyncedItem(
                        id=row['id'],
                        sync_version=row['sync_version'],
                        updated_at=row['updated_at'],
                    ))

            # ── 3. Sync Polígonos (upms) ─────────────────────────────────────
            for pol in payload.poligonos:
                fid = parse_uuid_or_none(pol.id)
                geom = pol.geometry
                props = pol.properties
                if not geom:
                    continue
                geom_json = json.dumps(geom)
                row = await conn.fetchrow("""
                    INSERT INTO upms (
                        id, geom, nombre, codigo_upm, notas,
                        created_by, updated_by, device_id, sync_version,
                        sync_dirty, updated_at
                    )
                    VALUES (
                        COALESCE($1::uuid, uuid_generate_v4()),
                        ST_GeomFromGeoJSON($2), $3, $4, $5,
                        $6::uuid, $6::uuid, $7, 0, false, NOW()
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        geom = EXCLUDED.geom,
                        nombre = EXCLUDED.nombre,
                        codigo_upm = EXCLUDED.codigo_upm,
                        notas = EXCLUDED.notas,
                        updated_by = $6::uuid,
                        device_id = $7,
                        sync_version = upms.sync_version + 1,
                        sync_dirty = false,
                        updated_at = NOW(),
                        deleted_at = NULL
                    RETURNING id::text, sync_version, updated_at
                """,
                fid, geom_json,
                props.get("nombre"), props.get("codigo_upm"), props.get("notas"),
                valid_user_id, device_id)

                if row:
                    result["poligonos"].append(SyncedItem(
                        id=row['id'],
                        sync_version=row['sync_version'],
                        updated_at=row['updated_at'],
                    ))

            # ── 4. Sincronizar Niveles ───────────────────────────────────────
            for item in payload.niveles:
                clean_id = parse_uuid_or_none(item.id)
                clean_est_id = parse_uuid_or_none(item.estructura_id)
                if clean_est_id:
                    row = await conn.fetchrow("""
                        INSERT INTO niveles (
                            id, estructura_id, numero, numero_locales,
                            created_by, updated_by, updated_at
                        )
                        VALUES (
                            COALESCE($1::uuid, uuid_generate_v4()), $2::uuid, $3, $4,
                            $5::uuid, $5::uuid, NOW()
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            estructura_id = EXCLUDED.estructura_id,
                            numero = EXCLUDED.numero,
                            numero_locales = EXCLUDED.numero_locales,
                            updated_by = $5::uuid,
                            updated_at = NOW()
                        RETURNING id::text, 1 as sync_version, updated_at;
                    """, clean_id, clean_est_id, item.numero, item.numero_locales or 1, valid_user_id)
                    if row:
                        result["niveles"].append(SyncedItem(id=row['id'], sync_version=row['sync_version'], updated_at=row['updated_at']))

            # ── 5. Sincronizar Locales ───────────────────────────────────────
            for item in payload.locales:
                clean_id = parse_uuid_or_none(item.id)
                clean_niv_id = parse_uuid_or_none(item.nivel_id)
                id_tipo_loc = item.id_tipo if item.id_tipo in (1, 2, 3, 4, 5) else 1
                id_cond_loc = item.id_condicion_local if item.id_condicion_local in (1, 2, 3, 4, 5) else None
                if clean_niv_id:
                    row = await conn.fetchrow("""
                        INSERT INTO locales (id, nivel_id, nombre_local, id_tipo, id_condicion_local, numero_hogares, descripcion, updated_at)
                        VALUES (COALESCE($1::uuid, uuid_generate_v4()), $2::uuid, $3, $4, $5, $6, $7, NOW())
                        ON CONFLICT (id) DO UPDATE SET
                            nivel_id = EXCLUDED.nivel_id,
                            nombre_local = EXCLUDED.nombre_local,
                            id_tipo = EXCLUDED.id_tipo,
                            id_condicion_local = EXCLUDED.id_condicion_local,
                            numero_hogares = EXCLUDED.numero_hogares,
                            descripcion = EXCLUDED.descripcion,
                            updated_at = NOW()
                        RETURNING id::text, 1 as sync_version, updated_at;
                    """, clean_id, clean_niv_id, item.nombre_local, id_tipo_loc, id_cond_loc, item.numero_hogares, item.descripcion)
                    if row:
                        result["locales"].append(SyncedItem(id=row['id'], sync_version=row['sync_version'], updated_at=row['updated_at']))

            # ── 6. Sincronizar Hogares ───────────────────────────────────────
            for item in payload.hogares:
                clean_id = parse_uuid_or_none(item.id)
                clean_loc_id = parse_uuid_or_none(item.local_id)
                id_idioma = item.id_idioma if (item.id_idioma and 1 <= item.id_idioma <= 20) else None
                id_sexo = item.id_sexo if item.id_sexo in (1, 2) else None
                if clean_loc_id:
                    row = await conn.fetchrow("""
                        INSERT INTO hogares (
                            id, local_id, jefe_familia, id_sexo, id_idioma, direccion, total_habitantes,
                            personas_0_5, personas_6_11, personas_12_17, personas_18_23,
                            personas_24_34, personas_35_44, personas_45_59, personas_60_69,
                            personas_70_79, personas_80_mas, personas_no_edad, updated_at
                        )
                        VALUES (
                            COALESCE($1::uuid, uuid_generate_v4()), $2::uuid, $3, $4, $5, $6, $7,
                            $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, NOW()
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            local_id = EXCLUDED.local_id,
                            jefe_familia = EXCLUDED.jefe_familia,
                            id_sexo = EXCLUDED.id_sexo,
                            id_idioma = EXCLUDED.id_idioma,
                            direccion = EXCLUDED.direccion,
                            total_habitantes = EXCLUDED.total_habitantes,
                            personas_0_5 = EXCLUDED.personas_0_5,
                            personas_6_11 = EXCLUDED.personas_6_11,
                            personas_12_17 = EXCLUDED.personas_12_17,
                            personas_18_23 = EXCLUDED.personas_18_23,
                            personas_24_34 = EXCLUDED.personas_24_34,
                            personas_35_44 = EXCLUDED.personas_35_44,
                            personas_45_59 = EXCLUDED.personas_45_59,
                            personas_60_69 = EXCLUDED.personas_60_69,
                            personas_70_79 = EXCLUDED.personas_70_79,
                            personas_80_mas = EXCLUDED.personas_80_mas,
                            personas_no_edad = EXCLUDED.personas_no_edad,
                            updated_at = NOW()
                        RETURNING id::text, 1 as sync_version, updated_at;
                    """, clean_id, clean_loc_id, item.jefe_familia, id_sexo, id_idioma, item.direccion,
                    item.total_habitantes, item.personas_0_5, item.personas_6_11, item.personas_12_17,
                    item.personas_18_23, item.personas_24_34, item.personas_35_44, item.personas_45_59,
                    item.personas_60_69, item.personas_70_79, item.personas_80_mas, item.personas_no_edad)
                    if row:
                        result["hogares"].append(SyncedItem(id=row['id'], sync_version=row['sync_version'], updated_at=row['updated_at']))

    return SyncResult(status="ok", synced=result)

