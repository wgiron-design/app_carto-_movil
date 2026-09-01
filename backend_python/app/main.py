from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.database import init_db, close_db
from app.routers import (
    capas, 
    features, 
    sync, 
    admin, 
    auth, 
    niveles, 
    locales, 
    hogares,
    roles,
    usuarios,
    jerarquia,
    upms,
    mi_cuenta
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield
    await close_db()

app = FastAPI(
    title="CartoDigital PostGIS & Security API",
    description="API REST asíncrona en Python para Carto Digital y Módulo de Seguridad Web",
    version="2.0.0",
    lifespan=lifespan
)

# CORS permisivo para desarrollo y frontend web local
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Inclusión de routers
app.include_router(auth.router)
app.include_router(mi_cuenta.router)
app.include_router(roles.router)
app.include_router(usuarios.router)
app.include_router(jerarquia.router)
app.include_router(upms.router)
app.include_router(capas.router)
app.include_router(features.router)
app.include_router(sync.router)
app.include_router(admin.router)
app.include_router(niveles.router)
app.include_router(niveles.estructuras_niveles_router)
app.include_router(locales.router)
app.include_router(hogares.router)

@app.get("/")
def read_root():
    return {
        "app": "CartoDigital PostGIS & Security API",
        "version": "2.0.0",
        "status": "online",
        "docs": "/docs",
        "admin": "/admin"
    }
