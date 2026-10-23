import asyncio
import sys
sys.stdout.reconfigure(encoding='utf-8')
import httpx

BASE_URL = "http://localhost:8000"

async def verify_fix():
    print("=" * 60)
    print("VERIFICACION DE SOLUCION: NIVELES Y LOCALES")
    print("=" * 60)

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=15.0) as client:
        # 1. Crear estructura con 2 niveles
        payload_estructura = {
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [-90.5, 14.6]},
            "properties": {
                "nombre": "Edificio Test 2 Niveles",
                "id_categoria": 1,
                "id_tipo": 1,
                "niveles_cantidad": 2,
                "estado": "presente"
            }
        }
        res_est = await client.post("/api/capas/estructuras/features", json=payload_estructura)
        print(f"[1] POST Estructura (niveles_cantidad=2): Status {res_est.status_code}")
        assert res_est.status_code == 200, f"Error creando estructura: {res_est.text}"
        est_data = res_est.json()
        est_id = est_data["id"]
        assert est_data["properties"]["niveles_cantidad"] == 2, f"Esperado 2, obtenido {est_data['properties']['niveles_cantidad']}"

        # 2. Consultar niveles de la estructura
        res_niveles = await client.get(f"/api/niveles/estructura/{est_id}")
        print(f"[2] GET Niveles de estructura: Status {res_niveles.status_code}")
        assert res_niveles.status_code == 200
        niv_data = res_niveles.json()
        print(f"    niveles_cantidad retornado: {niv_data.get('niveles_cantidad')}")
        assert niv_data.get("niveles_cantidad") == 2, f"FALLO: Retornó {niv_data.get('niveles_cantidad')}, se esperaba 2 (no 10)"

        # 3. Crear Nivel 1 en la estructura
        payload_nivel = {
            "numero_locales": 2,
            "descripcion": "Nivel 1 Prueba",
            "niveles_cantidad": 2
        }
        res_crear_nivel = await client.post(f"/api/niveles/estructura/{est_id}", json=payload_nivel)
        print(f"[3] POST Crear Nivel 1: Status {res_crear_nivel.status_code}")
        assert res_crear_nivel.status_code == 201
        nivel_data = res_crear_nivel.json()
        nivel_id = nivel_data["id"]
        assert nivel_data["numero"] == 1
        assert nivel_data["numero_locales"] == 2

        # 4. Crear Local en el Nivel 1
        payload_local = {
            "nombre_local": "Apartamento 101",
            "id_tipo": 1,
            "id_condicion_local": 1,
            "numero_hogares": 1,
            "descripcion": "Local de prueba creado"
        }
        res_local = await client.post(f"/api/locales/nivel/{nivel_id}", json=payload_local)
        print(f"[4] POST Crear Local: Status {res_local.status_code}")
        assert res_local.status_code == 201, f"Error creando local: {res_local.text}"
        local_data = res_local.json()
        local_id = local_data["id"]
        print(f"    Local creado ID={local_id}, Nombre='{local_data.get('nombre_local')}'")
        assert local_data.get("nombre_local") == "Apartamento 101"

        # 5. Consultar locales del nivel
        res_get_locales = await client.get(f"/api/locales/nivel/{nivel_id}")
        print(f"[5] GET Locales de nivel: Status {res_get_locales.status_code}")
        assert res_get_locales.status_code == 200
        lista_locales = res_get_locales.json()
        assert len(lista_locales.get("locales", [])) == 1
        print(f"    Total locales registrados: {lista_locales.get('locales_registrados')}")

        # 6. Limpieza: Eliminar estructura de prueba
        res_del = await client.delete(f"/api/capas/estructuras/features/{est_id}")
        print(f"[6] DELETE Estructura de prueba: Status {res_del.status_code}")
        assert res_del.status_code == 200

        print("\n" + "=" * 60)
        print(" [OK] TODAS LAS VALIDACIONES PASARON EXITOSAMENTE!")
        print("=" * 60)

if __name__ == "__main__":
    asyncio.run(verify_fix())
