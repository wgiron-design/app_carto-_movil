-- 1. Habilitar extensión espacial
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Catálogo de administración de capas
CREATE TABLE IF NOT EXISTS capas_registro (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre VARCHAR(100) NOT NULL,
    tipo_geometria VARCHAR(30) NOT NULL,    -- 'POINT', 'LINESTRING', 'POLYGON'
    tabla_origen VARCHAR(50) NOT NULL UNIQUE,
    descripcion TEXT,
    icono VARCHAR(50) DEFAULT 'layers',
    color VARCHAR(20) DEFAULT '#4FC3F7',
    activa BOOLEAN DEFAULT true,           -- Controla si la app móvil visualiza esta capa
    orden_visualizacion INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Capa Estructuras (Puntos)
CREATE TABLE IF NOT EXISTS estructuras (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    geom GEOMETRY(Point, 4326) NOT NULL,
    upm_id UUID,
    nombre VARCHAR(150),
    notas TEXT,
    categoria VARCHAR(50),                  -- 'formal', 'referencia'
    tipo_formal VARCHAR(50),
    tipo_referencia VARCHAR(50),
    estado VARCHAR(50),
    niveles_cantidad INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    sync_dirty BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_estructuras_geom ON estructuras USING GIST(geom);

-- 4. Capa Caminos (Líneas)
CREATE TABLE IF NOT EXISTS caminos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    geom GEOMETRY(LineString, 4326) NOT NULL,
    nombre VARCHAR(150),
    tipo VARCHAR(50),                       -- 'asfaltado', 'adoquinado', 'terraceria', 'vereda'
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    sync_dirty BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_caminos_geom ON caminos USING GIST(geom);

-- 5. Capa UPMs (Polígonos)
CREATE TABLE IF NOT EXISTS upms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    geom GEOMETRY(Polygon, 4326) NOT NULL,
    nombre VARCHAR(150),
    codigo_upm VARCHAR(50),
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    sync_dirty BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_upms_geom ON upms USING GIST(geom);

-- 6. Jerarquía Alfanumérica
CREATE TABLE IF NOT EXISTS niveles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    estructura_id UUID REFERENCES estructuras(id) ON DELETE CASCADE,
    numero INT NOT NULL,
    numero_locales INT DEFAULT 1,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS locales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nivel_id UUID REFERENCES niveles(id) ON DELETE CASCADE,
    nombre VARCHAR(100),
    uso_actual VARCHAR(100),
    ocupacion VARCHAR(100),
    numero_hogares INT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hogares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    local_id UUID REFERENCES locales(id) ON DELETE CASCADE,
    jefe_familia VARCHAR(150),
    sexo_jefe VARCHAR(20),
    idioma VARCHAR(50),
    total_habitantes INT,
    personas_0_5 INT, personas_6_11 INT, personas_12_17 INT, personas_18_23 INT,
    personas_24_34 INT, personas_35_44 INT, personas_45_59 INT, personas_60_69 INT,
    personas_70_79 INT, personas_80_mas INT, personas_no_edad INT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Carga de datos iniciales en el catálogo de capas
INSERT INTO capas_registro (nombre, tipo_geometria, tabla_origen, icono, color, activa, orden_visualizacion)
VALUES 
    ('Estructuras / Puntos', 'POINT', 'estructuras', 'place_outlined', '#4FC3F7', true, 1),
    ('Caminos / Líneas', 'LINESTRING', 'caminos', 'polyline_outlined', '#FFB74D', true, 2),
    ('UPMs / Polígonos', 'POLYGON', 'upms', 'pentagon_outlined', '#FF00FF', true, 3)
ON CONFLICT (tabla_origen) DO NOTHING;
