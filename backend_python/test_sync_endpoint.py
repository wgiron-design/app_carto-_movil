import asyncio
import httpx
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from app.main import app

async def test():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        # 1. Sync batch con punto, linea, poligono, nivel, local, hogar
        payload = {
            "puntos": [{
                "id": "11111111-1111-1111-1111-111111111111",
                "geometry": {"type": "Point", "coordinates": [-90.5, 14.6]},
                "properties": {
                    "nombre": "Test Estructura Sync",
                    "id_categoria": 1,
                    "id_tipo": 1,
                    "estado": "presente",
                    "niveles_cantidad": 1,
                    "notas": "Nota test"
                }
            }],
            "lineas": [{
                "id": "22222222-2222-2222-2222-222222222222",
                "geometry": {"type": "LineString", "coordinates": [[-90.5, 14.6], [-90.51, 14.61]]},
                "properties": {
                    "nombre": "Test Camino Sync",
                    "tipo": "terraceria",
                    "notas": "Nota camino"
                }
            }],
            "poligonos": [{
                "id": "33333333-3333-3333-3333-333333333333",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[[-90.5, 14.6], [-90.49, 14.6], [-90.49, 14.61], [-90.5, 14.61], [-90.5, 14.6]]]
                },
                "properties": {
                    "nombre": "Test UPM Sync",
                    "codigo_upm": "UPM-01",
                    "notas": "Nota upm"
                }
            }],
            "niveles": [{
                "id": "44444444-4444-4444-4444-444444444444",
                "estructura_id": "11111111-1111-1111-1111-111111111111",
                "numero": 1,
                "numero_locales": 1
            }],
            "locales": [{
                "id": "55555555-5555-5555-5555-555555555555",
                "nivel_id": "44444444-4444-4444-4444-444444444444",
                "nombre_local": "Local 1",
                "id_tipo": 1,
                "numero_hogares": 1
            }],
            "hogares": [{
                "id": "66666666-6666-6666-6666-666666666666",
                "local_id": "55555555-5555-5555-5555-555555555555",
                "jefe_familia": "Juan Perez",
                "total_habitantes": 3
            }],
            "user_id": None,
            "device_id": "emulator-5554"
        }

        print("Enviando POST /api/sync...")
        res = await client.post("/api/sync", json=payload)
        print("Status code:", res.status_code)
        print("Response body:", res.text)

if __name__ == "__main__":
    asyncio.run(test())
