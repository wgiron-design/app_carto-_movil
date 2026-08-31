import asyncio
import asyncpg
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'backend_python'))
from app.config import DATABASE_URL

STATEMENTS = [
    "ALTER TABLE estructuras ADD COLUMN IF NOT EXISTS id_estructura_user INTEGER NULL",
    "CREATE INDEX IF NOT EXISTS idx_estructuras_id_user ON estructuras (id_estructura_user)",
]

async def run_migration():
    db_url = DATABASE_URL.split('?')[0] if 'sslmode=' in DATABASE_URL else DATABASE_URL

    print("=" * 60)
    print(" EJECUTANDO MIGRACIÓN 006 (estructuras.id_estructura_user)")
    print("=" * 60)

    try:
        conn = await asyncpg.connect(dsn=db_url, ssl='require')
    except Exception as e:
        print(f"[ERROR] No se pudo conectar a la BD: {e}")
        return

    ok, skipped = 0, 0
    try:
        for i, stmt in enumerate(STATEMENTS, 1):
            try:
                await conn.execute(stmt)
                short = ' '.join(stmt.split()[:7])
                print(f"[OK]   {i:02d}. {short}...")
                ok += 1
            except Exception as e:
                short = ' '.join(stmt.split()[:7])
                print(f"[SKIP] {i:02d}. {short} → {e}")
                skipped += 1
    finally:
        await conn.close()

    print(f"\n[RESULTADO] OK={ok} | Omitidos={skipped}")
    print("[EXITO] Migración 006 finalizada.")
    print("=" * 60)

if __name__ == '__main__':
    asyncio.run(run_migration())
