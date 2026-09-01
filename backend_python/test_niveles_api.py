"""
Test de verificacion del flujo completo de Niveles:
  GET /api/niveles
  GET /api/niveles/estructura/{id}
  POST /api/niveles/estructura/{id}
  PATCH /api/niveles/{nivel_id}
  GET /api/estructuras/{id}/niveles
"""
import urllib.request
import urllib.error
import json
import sys

BASE = "http://localhost:8000"
FAKE_ESTRUCTURA_ID = "00000000-0000-0000-0000-000000000001"


def api(method, path, payload=None):
    url = BASE + path
    data = json.dumps(payload).encode() if payload else None
    headers = {"Content-Type": "application/json"} if payload else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            body = json.loads(r.read())
            return r.status, body
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = e.reason
        return e.code, body
    except Exception as e:
        return None, str(e)


print("=" * 60)
print("CHEQUEO API REST - MODULO NIVELES")
print("=" * 60)

# 1. Health check
s, d = api("GET", "/")
tag = "OK" if s == 200 else "FAIL"
print(f"\n[1] GET /  -> {s} {tag}")
if s != 200:
    print("    ERROR: Backend no responde.")
    sys.exit(1)

# 2. Listar todos los niveles
s, d = api("GET", "/api/niveles")
tag = "OK" if s == 200 and isinstance(d, list) else "FAIL"
count = len(d) if isinstance(d, list) else "N/A"
print(f"[2] GET /api/niveles -> {s} {tag} | {count} registros")

# 3. GET niveles de estructura inexistente (debe retornar 200 con lista vacia)
s, d = api("GET", f"/api/niveles/estructura/{FAKE_ESTRUCTURA_ID}")
ok = s == 200 and isinstance(d, dict) and d.get("niveles_registrados") == 0
tag = "OK" if ok else "FAIL"
nr = d.get("niveles_registrados") if isinstance(d, dict) else "N/A"
print(f"[3] GET /api/niveles/estructura/<inexistente> -> {s} {tag} | niveles_registrados={nr}")

# 4. GET alias /api/estructuras/{id}/niveles
s, d = api("GET", f"/api/estructuras/{FAKE_ESTRUCTURA_ID}/niveles")
tag = "OK" if s == 200 else "FAIL"
print(f"[4] GET /api/estructuras/<id>/niveles -> {s} {tag}")

# 5. POST crear nivel en estructura inexistente
print(f"\n[5] POST crear nivel en estructura que no existe en PG...")
s, d = api("POST", f"/api/niveles/estructura/{FAKE_ESTRUCTURA_ID}", {"numero_locales": 3})
tag = "OK" if s in (200, 201) else f"FAIL (puede ser FK error si catalogos vacios)"
print(f"    -> {s} {tag}")
nivel_id = None
if s in (200, 201):
    nivel_id = d.get("id")
    print(f"    nivel_id={nivel_id}, numero={d.get('numero')}, numero_locales={d.get('numero_locales')}")
else:
    print(f"    Respuesta: {d}")

# 6. PATCH nivel
if nivel_id:
    s, d = api("PATCH", f"/api/niveles/{nivel_id}", {"numero_locales": 5, "descripcion": "Test nivel"})
    tag = "OK" if s == 200 else "FAIL"
    print(f"[6] PATCH /api/niveles/<id> -> {s} {tag} | numero_locales={d.get('numero_locales')}")

    # 7. GET nivel por ID
    s, d = api("GET", f"/api/niveles/{nivel_id}")
    tag = "OK" if s == 200 else "FAIL"
    print(f"[7] GET /api/niveles/<id> -> {s} {tag} | descripcion={d.get('descripcion')}")

    # 8. DELETE locales excedentes
    s, d = api("DELETE", f"/api/niveles/{nivel_id}/locales-excedentes", {"numero_locales_nuevo": 2})
    tag = "OK" if s == 200 else "FAIL"
    print(f"[8] DELETE /api/niveles/<id>/locales-excedentes -> {s} {tag}")
else:
    print("[6-8] Skipped - nivel no fue creado")

print("\n" + "=" * 60)
print("Verifica que todos los pasos muestren OK")
print("=" * 60)
