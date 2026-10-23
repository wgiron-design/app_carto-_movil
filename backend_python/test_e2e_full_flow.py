import asyncio
import uuid
import sys
import httpx
from app.main import app
from app.database import init_db, close_db, get_db_pool

async def run_e2e_validation():
    print("=" * 70)
    print(" [QA E2E] VALIDACION INTEGRAL: INGRESO Y EDICION (ESTRUCTURA -> NIVEL -> LOCAL -> HOGAR)")
    print("=" * 70)

    try:
        await init_db()
        pool = await get_db_pool()
        print("[OK] Conectado a PostgreSQL/Neon.")
    except Exception as e:
        print(f"[FAIL] Error conectando a PostgreSQL: {e}")
        return False

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        # Generar IDs para la prueba y obtener usuario real de BD
        est_id = str(uuid.uuid4())
        user_row = await pool.fetchrow("SELECT id::text FROM users WHERE is_active = true LIMIT 1")
        test_user_id = user_row["id"] if user_row else None
        
        # ─────────────────────────────────────────────────────────────
        # 1. CREACION DE ESTRUCTURA (DATOS ALFANUMERICOS)
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 1: Creacion de Nueva Estructura ---")
        payload_est = {
            "id": est_id,
            "geometry": {
                "type": "Point",
                "coordinates": [-90.615105241, 16.122804657]
            },
            "properties": {
                "nombre": "Edificio Residencial Las Palmas",
                "id_categoria": 1,
                "id_tipo": 1,
                "id_estructura_user": 4501,
                "estado": "presente",
                "niveles_cantidad": 2,
                "notas": "Estructura principal construida en 2024",
                "created_by": test_user_id,
                "updated_by": test_user_id,
                "device_id": "device_qa_test"
            }
        }
        res = await client.post("/api/capas/estructuras/features", json=payload_est)
        print(f"POST /api/capas/estructuras/features -> Status: {res.status_code}")
        assert res.status_code in (200, 201), f"Error creando estructura: {res.text}"
        data_est = res.json()
        props = data_est.get("properties", {})
        print(f"  [OK] Estructura creada con ID: {est_id}")
        print(f"       Nombre: {props.get('nombre')}, Niveles esperados: {props.get('niveles_cantidad')}, Notas: {props.get('notas')}")
        assert props.get("nombre") == "Edificio Residencial Las Palmas"
        assert props.get("niveles_cantidad") == 2

        # ─────────────────────────────────────────────────────────────
        # 2. EDICION DE ESTRUCTURA (DATOS ALFANUMERICOS)
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 2: Edicion de Datos Alfanumericos de Estructura ---")
        payload_est_edit = {
            "id": est_id,
            "geometry": {
                "type": "Point",
                "coordinates": [-90.615105241, 16.122804657]
            },
            "properties": {
                "nombre": "Torre Residencial Las Palmas (Editada)",
                "id_categoria": 1,
                "id_tipo": 1,
                "id_estructura_user": 4502,
                "estado": "presente",
                "niveles_cantidad": 3,
                "notas": "Estructura ampliada a 3 niveles",
                "created_by": test_user_id,
                "updated_by": test_user_id,
                "device_id": "device_qa_test"
            }
        }
        res_edit = await client.post("/api/capas/estructuras/features", json=payload_est_edit)
        print(f"POST (UPSERT) /api/capas/estructuras/features -> Status: {res_edit.status_code}")
        assert res_edit.status_code in (200, 201), f"Error editando estructura: {res_edit.text}"
        props_edit = res_edit.json().get("properties", {})
        print(f"  [OK] Estructura actualizada.")
        print(f"       Nuevo Nombre: {props_edit.get('nombre')}")
        print(f"       Niveles actualizados: {props_edit.get('niveles_cantidad')}")
        print(f"       Notas actualizadas: {props_edit.get('notas')}")
        assert props_edit.get("nombre") == "Torre Residencial Las Palmas (Editada)"
        assert props_edit.get("niveles_cantidad") == 3
        assert props_edit.get("notas") == "Estructura ampliada a 3 niveles"

        # ─────────────────────────────────────────────────────────────
        # 3. CREACION DE NIVEL
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 3: Creacion de Nivel 1 en la Estructura ---")
        payload_nivel = {
            "numero_locales": 2,
            "descripcion": "Primer Nivel - Planta Comercial"
        }
        res_niv = await client.post(f"/api/niveles/estructura/{est_id}", json=payload_nivel)
        print(f"POST /api/niveles/estructura/{est_id} -> Status: {res_niv.status_code}")
        assert res_niv.status_code in (200, 201), f"Error creando nivel: {res_niv.text}"
        nivel_data = res_niv.json()
        nivel_id = nivel_data["id"]
        print(f"  [OK] Nivel creado con ID: {nivel_id}")
        print(f"       Numero nivel: {nivel_data.get('numero')}, Locales esperados: {nivel_data.get('numero_locales')}, Desc: {nivel_data.get('descripcion')}")
        assert nivel_data.get("numero") == 1
        assert nivel_data.get("numero_locales") == 2

        # ─────────────────────────────────────────────────────────────
        # 4. EDICION DE NIVEL
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 4: Edicion de Datos Alfanumericos de Nivel 1 ---")
        payload_niv_edit = {
            "numero_locales": 3,
            "descripcion": "Primer Nivel Comercial (Modificado)"
        }
        res_niv_edit = await client.patch(f"/api/niveles/{nivel_id}", json=payload_niv_edit)
        print(f"PATCH /api/niveles/{nivel_id} -> Status: {res_niv_edit.status_code}")
        assert res_niv_edit.status_code == 200, f"Error editando nivel: {res_niv_edit.text}"
        niv_edit_data = res_niv_edit.json()
        print(f"  [OK] Nivel editado exitosamente.")
        print(f"       Locales actualizados: {niv_edit_data.get('numero_locales')}")
        print(f"       Descripcion actualizada: {niv_edit_data.get('descripcion')}")
        assert niv_edit_data.get("numero_locales") == 3
        assert niv_edit_data.get("descripcion") == "Primer Nivel Comercial (Modificado)"

        # ─────────────────────────────────────────────────────────────
        # 5. CREACION DE LOCAL
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 5: Creacion de Local en Nivel 1 ---")
        payload_local = {
            "nombre_local": "Farmacia Central",
            "id_tipo": 1,
            "id_condicion_local": 1,
            "numero_hogares": 1,
            "descripcion": "Local 101 - Esquina norte"
        }
        res_loc = await client.post(f"/api/locales/nivel/{nivel_id}", json=payload_local)
        print(f"POST /api/locales/nivel/{nivel_id} -> Status: {res_loc.status_code}")
        assert res_loc.status_code in (200, 201), f"Error creando local: {res_loc.text}"
        local_data = res_loc.json()
        local_id = local_data["id"]
        print(f"  [OK] Local creado con ID: {local_id}")
        print(f"       Nombre: {local_data.get('nombre_local')}, Tipo: {local_data.get('id_tipo')}, Hogares esperados: {local_data.get('numero_hogares')}")
        assert local_data.get("nombre_local") == "Farmacia Central"
        assert local_data.get("numero_hogares") == 1

        # ─────────────────────────────────────────────────────────────
        # 6. EDICION DE LOCAL
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 6: Edicion de Datos Alfanumericos de Local ---")
        payload_loc_edit = {
            "nombre_local": "Farmacia y Minisuper Central (Editado)",
            "numero_hogares": 2,
            "descripcion": "Local 101 - Remodelado y ampliado"
        }
        res_loc_edit = await client.patch(f"/api/locales/{local_id}", json=payload_loc_edit)
        print(f"PATCH /api/locales/{local_id} -> Status: {res_loc_edit.status_code}")
        assert res_loc_edit.status_code == 200, f"Error editando local: {res_loc_edit.text}"
        loc_edit_data = res_loc_edit.json()
        print(f"  [OK] Local editado exitosamente.")
        print(f"       Nuevo Nombre: {loc_edit_data.get('nombre_local')}")
        print(f"       Hogares esperados: {loc_edit_data.get('numero_hogares')}")
        print(f"       Nueva Descripcion: {loc_edit_data.get('descripcion')}")
        assert loc_edit_data.get("nombre_local") == "Farmacia y Minisuper Central (Editado)"
        assert loc_edit_data.get("numero_hogares") == 2
        assert loc_edit_data.get("descripcion") == "Local 101 - Remodelado y ampliado"

        # ─────────────────────────────────────────────────────────────
        # 7. CREACION DE HOGAR
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 7: Creacion de Hogar en Local ---")
        payload_hogar = {
            "jefe_familia": "Carlos Rodriguez",
            "id_sexo": 1,
            "id_idioma": 1,
            "direccion": "Apartamento 101-A",
            "total_habitantes": 4,
            "personas_0_5": 1,
            "personas_24_34": 2,
            "personas_60_69": 1
        }
        res_hog = await client.post(f"/api/hogares/local/{local_id}", json=payload_hogar)
        print(f"POST /api/hogares/local/{local_id} -> Status: {res_hog.status_code}")
        assert res_hog.status_code in (200, 201), f"Error creando hogar: {res_hog.text}"
        hogar_data = res_hog.json()
        hogar_id = hogar_data["id"]
        print(f"  [OK] Hogar creado con ID: {hogar_id}")
        print(f"       Jefe de Familia: {hogar_data.get('jefe_familia')}, Total Habitantes: {hogar_data.get('total_habitantes')}")
        assert hogar_data.get("jefe_familia") == "Carlos Rodriguez"
        assert hogar_data.get("total_habitantes") == 4

        # ─────────────────────────────────────────────────────────────
        # 8. EDICION DE HOGAR
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 8: Edicion de Datos Alfanumericos de Hogar ---")
        payload_hog_edit = {
            "jefe_familia": "Carlos Rodriguez Martinez (Editado)",
            "total_habitantes": 5,
            "personas_6_11": 1
        }
        res_hog_edit = await client.patch(f"/api/hogares/{hogar_id}", json=payload_hog_edit)
        print(f"PATCH /api/hogares/{hogar_id} -> Status: {res_hog_edit.status_code}")
        assert res_hog_edit.status_code == 200, f"Error editando hogar: {res_hog_edit.text}"
        hog_edit_data = res_hog_edit.json()
        print(f"  [OK] Hogar editado exitosamente.")
        print(f"       Nuevo Jefe: {hog_edit_data.get('jefe_familia')}")
        print(f"       Total Habitantes: {hog_edit_data.get('total_habitantes')}")
        print(f"       Personas 6-11: {hog_edit_data.get('personas_6_11')}")
        assert hog_edit_data.get("jefe_familia") == "Carlos Rodriguez Martinez (Editado)"
        assert hog_edit_data.get("total_habitantes") == 5
        assert hog_edit_data.get("personas_6_11") == 1

        # ─────────────────────────────────────────────────────────────
        # 9. VALIDACION DE TOPES (409 CONFLICT)
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 9: Validacion de Topes Maximos ---")
        # Ya tenemos 1 hogar, límite es 2. Creemos el segundo:
        res_hog2 = await client.post(f"/api/hogares/local/{local_id}", json={"jefe_familia": "Hogar 2", "total_habitantes": 2})
        print(f"Creando 2do Hogar (Límite=2) -> Status: {res_hog2.status_code}")
        assert res_hog2.status_code in (200, 201)
        hogar2_id = res_hog2.json()["id"]

        # Intentar crear 3er Hogar (debe fallar con 409)
        res_hog3 = await client.post(f"/api/hogares/local/{local_id}", json={"jefe_familia": "Hogar 3 Excedente", "total_habitantes": 1})
        print(f"Intentando 3er Hogar (Supera límite) -> Status: {res_hog3.status_code}")
        assert res_hog3.status_code == 409, f"Debería retornar 409 pero retornó {res_hog3.status_code}"
        print(f"  [OK] Tope de hogares protegido correctamente con 409: {res_hog3.json()['detail']['message']}")

        # ─────────────────────────────────────────────────────────────
        # 10. VALIDACION RESILIENCIA OFFLINE (_asegurar_local_existente)
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 10: Validacion de Salvaguarda Offline de Hogares ---")
        offline_local_id = str(uuid.uuid4())
        res_offline_hog = await client.post(
            f"/api/hogares/local/{offline_local_id}",
            json={"jefe_familia": "Familia Offline", "total_habitantes": 3}
        )
        print(f"POST Hogar en Local Offline ({offline_local_id}) -> Status: {res_offline_hog.status_code}")
        assert res_offline_hog.status_code in (200, 201), f"Fallo al asegurar local offline: {res_offline_hog.text}"
        offline_hog_data = res_offline_hog.json()
        print(f"  [OK] Local base asegurado automáticamente y hogar guardado con ID: {offline_hog_data['id']}")
        # Limpiar hogar offline
        await client.delete(f"/api/hogares/{offline_hog_data['id']}")

        # ─────────────────────────────────────────────────────────────
        # 11. LIMPIEZA DE DATOS DE PRUEBA
        # ─────────────────────────────────────────────────────────────
        print("\n--- PASO 11: Limpieza de Registros de Prueba ---")
        del_h1 = await client.delete(f"/api/hogares/{hogar_id}")
        del_h2 = await client.delete(f"/api/hogares/{hogar2_id}")
        del_loc = await client.delete(f"/api/locales/{local_id}")
        del_niv = await client.delete(f"/api/niveles/{nivel_id}")
        del_est = await client.delete(f"/api/capas/estructuras/features/{est_id}")
        print(f"  [OK] Registros eliminados: Hogares({del_h1.status_code},{del_h2.status_code}), Local({del_loc.status_code}), Nivel({del_niv.status_code}), Estructura({del_est.status_code})")

    print("\n" + "=" * 70)
    print(" [QA E2E] RESULTADO: TODOS LOS FLUJOS DE INGRESO Y EDICION FUNCIONAN AL 100%!")
    print("=" * 70)
    return True

if __name__ == "__main__":
    success = asyncio.run(run_e2e_validation())
    sys.exit(0 if success else 1)
