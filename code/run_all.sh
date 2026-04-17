#!/bin/bash
# =============================================================================
# run_all.sh
# Autopsia Electoral ONPE 2026 — Pipeline completo
# Ejecutar desde la raíz del proyecto:
#   bash code/run_all.sh
# =============================================================================

set -e

# Siempre ejecutar desde la raíz del proyecto
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo ""
echo "============================================"
echo "  AUTOPSIA ELECTORAL ONPE 2026"
echo "  $(date '+%d/%m/%Y %H:%M:%S')"
echo "============================================"
echo ""

# ── 0. Scraper ───────────────────────────────────────────────────────────────
echo "[ 0/6 ] Descargando actas nuevas desde STAE-ONPE..."
caffeinate -i python3 code/00_scrape_missing.py --workers 100
echo ""

# ── 1. Limpieza ──────────────────────────────────────────────────────────────
echo "[ 1/6 ] Limpiando datos y construyendo panel..."
Rscript code/01_clean.R
echo ""

# ── 2. Modelo ────────────────────────────────────────────────────────────────
echo "[ 2/6 ] Estimando modelo (2-3 minutos)..."
Rscript code/02_model.R
echo ""

# ── 3. Imputación ────────────────────────────────────────────────────────────
echo "[ 3/6 ] Calculando votos imputados..."
Rscript code/03_impute.R
echo ""

# ── 4. Robustez ──────────────────────────────────────────────────────────────
echo "[ 4/6 ] Verificaciones de robustez..."
Rscript code/04_robustness.R
echo ""

# ── 5. Figuras ───────────────────────────────────────────────────────────────
echo "[ 5/6 ] Generando figuras y mapas..."
Rscript code/05_figures.R
echo ""

# ── 6. Paper ─────────────────────────────────────────────────────────────────
echo "[ 6/6 ] Generando paper PDF..."
Rscript -e "rmarkdown::render('autopsia_onpe2026.Rmd', output_format='pdf_document')"
echo ""

# ── Resumen ──────────────────────────────────────────────────────────────────
echo "============================================"
echo "  ✓ Pipeline completo"
echo "  $(date '+%d/%m/%Y %H:%M:%S')"
echo "============================================"
echo ""

python3 - << 'PYEOF'
import pandas as pd
try:
    df   = pd.read_csv("data/raw/lima_2026.csv", encoding="latin1")
    dist = pd.read_csv("data/raw/districts.csv", encoding="latin1")
    dist["polling_tables"] = pd.to_numeric(
        dist["polling_tables"].astype(str).str.replace(",",""), errors="coerce")
    total_esp = int(dist["polling_tables"].sum())
    pct = round(len(df) / total_esp * 100, 1)
    print(f"  Mesas procesadas:  {len(df):,} / {total_esp:,} ({pct}%)")
    nk = pd.read_csv("output/tables/numeros_clave.csv")
    print(f"  Votantes perdidos: {int(nk['votantes_perdidos'].iloc[0]):,}")
    print(f"  Votos netos RP:    {int(nk['diferencia_imputable'].iloc[0]):,}")
except Exception as e:
    print(f"  (no se pudo leer resumen: {e})")
PYEOF

echo ""
echo "  Para publicar en GitHub:"
echo "  git add -A && git commit -m 'Actualización: \$(python3 -c \"import pandas as pd; df=pd.read_csv(\\\"data/raw/lima_2026.csv\\\", encoding=\\\"latin1\\\"); print(f\\\"{round(len(df)/29266*100,1)}% mesas\\\")\")'  && git push"
echo ""
