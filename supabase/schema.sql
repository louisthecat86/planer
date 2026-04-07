-- =============================================================================
-- Produktion Planer — Supabase/Postgres Schema
-- =============================================================================
--
-- Dieses Schema spiegelt das lokale drift/SQLite-Schema der App.
-- Es wird in Phase 6 (Sync) deployed, liegt aber jetzt schon hier,
-- damit das Datenmodell von Anfang an cloud-kompatibel entworfen wird.
--
-- Konventionen:
--   - IDs sind TEXT (UUIDs, app-generiert) — nicht BIGSERIAL, weil die App
--     IDs offline selbst vergibt und Kollisionen mit der Cloud vermieden
--     werden müssen.
--   - Jede Tabelle hat created_at, updated_at, deleted_at (Soft-Delete).
--   - updated_at wird via Trigger automatisch aktualisiert.
--   - RLS-Policies werden separat in Phase 6 ergänzt.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Trigger-Funktion: updated_at auf NOW() setzen bei jedem UPDATE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
    id                  TEXT PRIMARY KEY,
    artikelnummer       TEXT NOT NULL UNIQUE,
    artikelbezeichnung  TEXT NOT NULL,
    beschreibung        TEXT,
    notizen             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_products_artikelnummer ON products(artikelnummer);
CREATE TRIGGER products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- product_steps
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_steps (
    id                          TEXT PRIMARY KEY,
    product_id                  TEXT NOT NULL REFERENCES products(id),
    reihenfolge                 INTEGER NOT NULL,
    abteilung                   TEXT NOT NULL,
    basis_menge_kg              DOUBLE PRECISION NOT NULL,
    basis_dauer_minuten         DOUBLE PRECISION NOT NULL,
    fix_zeit_minuten            DOUBLE PRECISION,
    dauer_std_abweichung        DOUBLE PRECISION,
    basis_mitarbeiter           INTEGER NOT NULL,
    basis_anzahl_messungen      INTEGER NOT NULL DEFAULT 0,
    maschinen_einstellungen_json TEXT,
    notizen                     TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at                  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_product_steps_product_id
    ON product_steps(product_id, reihenfolge);
CREATE TRIGGER product_steps_updated_at BEFORE UPDATE ON product_steps
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- raw_materials
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_materials (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    artikelnummer   TEXT,
    einheit         TEXT NOT NULL,
    lieferant       TEXT,
    lead_time_tage  INTEGER,
    chargen_pflicht BOOLEAN NOT NULL DEFAULT TRUE,
    notizen         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);
CREATE TRIGGER raw_materials_updated_at BEFORE UPDATE ON raw_materials
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- product_raw_materials
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_raw_materials (
    id                    TEXT PRIMARY KEY,
    product_id            TEXT NOT NULL REFERENCES products(id),
    raw_material_id       TEXT NOT NULL REFERENCES raw_materials(id),
    menge_pro_kg_produkt  DOUBLE PRECISION NOT NULL,
    toleranz_prozent      DOUBLE PRECISION,
    notizen               TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMPTZ
);
CREATE TRIGGER product_raw_materials_updated_at BEFORE UPDATE ON product_raw_materials
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- raw_material_batches (HACCP Chargen + Lagerbestand)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_material_batches (
    id              TEXT PRIMARY KEY,
    raw_material_id TEXT NOT NULL REFERENCES raw_materials(id),
    chargennummer   TEXT NOT NULL,
    mhd             TIMESTAMPTZ,
    eingangs_datum  TIMESTAMPTZ NOT NULL,
    menge_initial   DOUBLE PRECISION NOT NULL,
    menge_aktuell   DOUBLE PRECISION NOT NULL,
    einheit         TEXT NOT NULL,
    lieferant       TEXT,
    notizen         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_batches_raw_material_id
    ON raw_material_batches(raw_material_id);
CREATE TRIGGER raw_material_batches_updated_at BEFORE UPDATE ON raw_material_batches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- production_tasks
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS production_tasks (
    id                      TEXT PRIMARY KEY,
    product_id              TEXT NOT NULL REFERENCES products(id),
    menge_kg                DOUBLE PRECISION NOT NULL,
    datum                   TIMESTAMPTZ NOT NULL,
    abteilung               TEXT NOT NULL,
    start_zeit              TEXT,
    geplante_dauer_minuten  DOUBLE PRECISION NOT NULL,
    geplante_mitarbeiter    INTEGER NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'geplant',
    parent_task_id          TEXT REFERENCES production_tasks(id),
    notizen                 TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_production_tasks_datum_abteilung
    ON production_tasks(datum, abteilung);
CREATE TRIGGER production_tasks_updated_at BEFORE UPDATE ON production_tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- production_runs (Ist-Erfassung, Futter für Lernlogik)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS production_runs (
    id                           TEXT PRIMARY KEY,
    task_id                      TEXT NOT NULL REFERENCES production_tasks(id),
    tatsaechliche_dauer_minuten  DOUBLE PRECISION NOT NULL,
    tatsaechliche_mitarbeiter    INTEGER NOT NULL,
    tatsaechliche_menge_kg       DOUBLE PRECISION NOT NULL,
    verwendete_chargen_json      TEXT,
    notizen                      TEXT,
    erfasst_von                  TEXT,
    erfasst_am                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at                   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_production_runs_task_id
    ON production_runs(task_id);
CREATE TRIGGER production_runs_updated_at BEFORE UPDATE ON production_runs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- task_dependencies
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_dependencies (
    id           TEXT PRIMARY KEY,
    from_task_id TEXT NOT NULL REFERENCES production_tasks(id),
    to_task_id   TEXT NOT NULL REFERENCES production_tasks(id),
    typ          TEXT NOT NULL DEFAULT 'finish_to_start',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ
);
CREATE TRIGGER task_dependencies_updated_at BEFORE UPDATE ON task_dependencies
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- order_list_items (Bestellliste mit Abhaken)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_list_items (
    id                 TEXT PRIMARY KEY,
    raw_material_id    TEXT NOT NULL REFERENCES raw_materials(id),
    woche_start_datum  TIMESTAMPTZ NOT NULL,
    benoetigte_menge   DOUBLE PRECISION NOT NULL,
    einheit            TEXT NOT NULL,
    bestellt           BOOLEAN NOT NULL DEFAULT FALSE,
    bestellt_am        TIMESTAMPTZ,
    geliefert          BOOLEAN NOT NULL DEFAULT FALSE,
    geliefert_am       TIMESTAMPTZ,
    notizen            TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at         TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_order_list_woche
    ON order_list_items(woche_start_datum);
CREATE TRIGGER order_list_items_updated_at BEFORE UPDATE ON order_list_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
