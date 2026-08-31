-- =============================================================================
-- Script 008: Agregar id_estructura_user en estructuras (PostgreSQL / PostGIS)
-- =============================================================================

ALTER TABLE estructuras
    ADD COLUMN IF NOT EXISTS id_estructura_user INTEGER NULL;

CREATE INDEX IF NOT EXISTS idx_estructuras_id_user ON estructuras (id_estructura_user);
