#!/bin/bash
# =============================================================================
# launch.sh
# Autopsia Electoral ONPE 2026 — Lanzamiento completo
# Ejecutar desde la raíz del proyecto: bash code/launch.sh
# =============================================================================

set -e

echo ""
echo "============================================"
echo "  AUTOPSIA ELECTORAL ONPE 2026"
echo "  Preparando lanzamiento"
echo "============================================"
echo ""

PROJECT="$HOME/Documents/datapol/peru/election_day/autopsy_onpe2026"
cd "$PROJECT"

# ── 1. Estructura de carpetas para GitHub Pages ──────────────────────────────
echo "[ 1 ] Preparando estructura para GitHub Pages..."

# GitHub Pages sirve desde la raíz — mover index.html a raíz
cp web/index.html index.html

# El PDF se genera en la raíz junto al .Rmd
if [ -f "autopsia_onpe2026.pdf" ]; then
  echo "  ✓ Paper PDF listo en raíz del proyecto"
else
  echo "  ⚠ Paper PDF no encontrado — ejecutar: Rscript -e \"rmarkdown::render('autopsia_onpe2026.Rmd', output_format='pdf_document')\""
fi

echo "  ✓ index.html listo en raíz"

# ── 2. Crear .gitignore ───────────────────────────────────────────────────────
echo ""
echo "[ 2 ] Creando .gitignore..."
cat > .gitignore << 'EOF'
# R
*.Rhistory
*.RData
*.Rproj.user
*.knit.md
*.tex
*.log

# Python
__pycache__/
*.pyc
.DS_Store

# Datos intermedios — no subir RDS (son grandes y regenerables)
data/clean/*.rds

# Pero SÍ subir los CSVs de output (son los que lee el sitio web)
!output/tables/*.csv
!data/clean/cobertura_distritos.csv
EOF
echo "  ✓ .gitignore creado"

# ── 3. Inicializar repositorio Git ───────────────────────────────────────────
echo ""
echo "[ 3 ] Inicializando repositorio Git..."
if [ ! -d ".git" ]; then
  git init
  echo "  ✓ Repositorio Git inicializado"
else
  echo "  ✓ Repositorio Git ya existe"
fi

# ── 4. Commit inicial ────────────────────────────────────────────────────────
echo ""
echo "[ 4 ] Preparando commit inicial..."
git add .
git commit -m "Lanzamiento inicial: Autopsia Electoral ONPE 2026

- Análisis econométrico del impacto de fallas logísticas en apertura de mesas
- Modelo: spline cúbico restringido + efectos fijos de distrito y año
- Panel histórico 2006-2026, Lima y Callao
- Sitio web interactivo con mapas y simulador de sensibilidad
- Paper académico completo con referencias
- Pipeline reproducible completo (scraper + R + figuras)
- $(python3 -c "import pandas as pd; df=pd.read_csv('data/raw/lima_2026.csv', encoding='latin1'); print(f'{len(df):,} mesas procesadas ({round(len(df)/29266*100,1)}% del total esperado)')")" 2>/dev/null || \
git commit -m "Lanzamiento inicial: Autopsia Electoral ONPE 2026"
echo "  ✓ Commit inicial listo"

echo ""
echo "============================================"
echo "  PRÓXIMOS PASOS MANUALES"
echo "============================================"
echo ""
echo "  1. Crear repositorio en GitHub:"
echo "     → Ir a github.com/new"
echo "     → Nombre: autopsy_onpe2026"
echo "     → Público (para máxima transparencia)"
echo "     → NO inicializar con README (ya tienes uno)"
echo ""
echo "  2. Conectar y subir:"
echo "     git remote add origin https://github.com/[TU_USUARIO]/autopsy_onpe2026.git"
echo "     git branch -M main"
echo "     git push -u origin main"
echo ""
echo "  3. Activar GitHub Pages:"
echo "     → Settings → Pages → Source: main branch, / (root)"
echo "     → El sitio estará en: https://[TU_USUARIO].github.io/autopsy_onpe2026"
echo ""
echo "  4. Para actualizar cuando lleguen nuevas actas:"
echo "     bash code/run_all.sh"
echo "     git add -A && git commit -m 'Actualización: X% mesas procesadas'"
echo "     git push"
echo ""
echo "  El sitio se actualiza automáticamente al hacer push."
echo ""
