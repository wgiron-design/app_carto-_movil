import asyncio
import asyncpg
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'backend_python'))
from app.config import DATABASE_URL

async def check_schema():
    db_url = DATABASE_URL.split('?')[0] if 'sslmode=' in DATABASE_URL else DATABASE_URL
    conn = await asyncpg.connect(dsn=db_url, ssl='require')
    
    fk_rows = await conn.fetch('''
        SELECT tc.table_name, kcu.column_name, ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name 
        FROM information_schema.table_constraints AS tc 
        JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name 
        JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name 
        WHERE tc.constraint_type = 'FOREIGN KEY'
    ''')
    rows = await conn.fetch("SELECT id, username, email FROM users")
    print("=== USERS ===")
    for r in rows:
        print(dict(r))
    print()

    await conn.close()

if __name__ == '__main__':
    asyncio.run(check_schema())


