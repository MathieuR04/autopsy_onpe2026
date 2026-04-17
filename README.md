# Autopsia Electoral ONPE 2026

**Mathieu Rojas**

> *"La autopsia ha concluido que las fallas logísticas que retrasaron la apertura de mesas de sufragio el 12 de abril de 2026 vulneraron el derecho al voto de miles de ciudadanos en Lima y Callao, y generaron un impacto estimado y estadísticamente significativo sobre la brecha entre los candidatos Rafael López Aliaga y Roberto Sánchez."*

---

## ¿Qué es esto?

Este repositorio contiene el código, los datos y el análisis completo de una investigación econométrica sobre el impacto de las fallas logísticas de la ONPE durante las Elecciones Generales 2026 en el Perú.

> **Aclaración importante:** Este análisis **no alega fraude electoral**. No existe evidencia de manipulación intencional de resultados. Lo que documentamos es distinto y más preciso: una falla logística de responsabilidad comprobada — el incumplimiento de la empresa Galaga — que tuvo consecuencias medibles sobre la participación electoral y que, en el contexto de una elección extremadamente reñida, pudo haber alterado el resultado final. La distinción importa: fraude implica intención; falla logística implica negligencia con consecuencias electorales.

La empresa **Servicios Generales Galaga S.A.C.**, contratada por la ONPE para el transporte del material electoral, no cumplió con entregar los camiones requeridos a tiempo. Esto provocó retrasos masivos en la apertura de mesas de sufragio en Lima Sur y otras zonas de Lima Metropolitana y Callao, impidiendo que miles de ciudadanos ejercieran su derecho al voto.

Este análisis estima:
1. **¿Cuántos votantes no pudieron votar?** — usando un modelo econométrico de efectos fijos con spline cúbico restringido
2. **¿Cómo habrían votado?** — imputando votos a partir de los resultados observados en cada mesa
3. **¿Qué tan robusto es el resultado?** — con verificaciones de robustez calibradas empíricamente

> **Nota sobre cobertura:** El análisis cubre actualmente el ~90% de las mesas de sufragio esperadas. Las mesas faltantes se concentran desproporcionadamente en los distritos con mayores retrasos — San Juan de Miraflores, Villa El Salvador, Lurín y Pachacámac. Esto significa que las estimaciones actuales son probablemente **conservadoras**: el impacto real podría ser mayor. El análisis se actualiza automáticamente conforme la ONPE publica nuevas actas digitales.

---

## Resultados principales

> ⚠️ **Nota:** Los resultados se actualizan automáticamente conforme se publican nuevas actas en el sistema STAE de la ONPE. Los números a continuación corresponden al **90.2% de mesas procesadas**.

| Indicador | Estimación |
|-----------|-----------|
| Mesas de sufragio con retraso significativo (≥120 min) | 3,139 |
| Votantes que no pudieron sufragar por los retrasos | ~10,700 |
| Votos netos imputados a favor de RP sobre JPP | ~10,765 |
| Resultado en el escenario más conservador | RP positivo |

---

## Metodología en pocas palabras

Comparamos el ausentismo de mesas que abrieron tarde con el que habrían tenido de haber abierto a tiempo, controlando por las características históricas de cada distrito (2006–2021). Solo atribuimos efectos donde el modelo muestra significancia estadística — retrasos mayores a 2 horas.

Para más detalle, ver el [paper completo](autopsia_onpe2026.pdf) o la [sección de metodología](web/metodologia.html).

---

## Estructura del repositorio

```
autopsy_onpe2026/
├── code/
│   ├── 00_scrape_missing.py   # Descarga actas desde STAE-ONPE
│   ├── 01_clean.R             # Limpieza y construcción del panel
│   ├── 02_model.R             # Modelo principal (spline + efectos fijos)
│   ├── 03_impute.R            # Imputación contrafactual de votos
│   ├── 04_robustness.R        # Verificaciones de robustez
│   ├── 05_figures.R           # Todas las figuras y mapas
│   └── run_all.sh             # Pipeline completo en un comando
├── data/
│   ├── raw/                   # Datos originales (CSV + shapefile)
│   └── clean/                 # Datos procesados (RDS)
├── output/
│   ├── figures/               # Todas las figuras en PNG
│   └── tables/                # Tablas de resultados
├── paper/
│   └── autopsia_onpe2026.Rmd  # Paper académico completo
├── web/
│   └── index.html             # Sitio web público
└── README.md
```

---

## Cómo reproducir el análisis

### Requisitos

**Python:** `pip install requests pdfplumber pandas tqdm`

**R:** 
```r
install.packages(c("tidyverse", "fixest", "splines", "lubridate",
                   "janitor", "here", "sf", "scales", "patchwork",
                   "ggtext", "hms"))
```

### Ejecución

```bash
# Desde la raíz del proyecto
bash code/run_all.sh
```

Esto ejecuta el pipeline completo: descarga actas nuevas, limpia datos, estima el modelo, imputa votos, calcula robustez y genera todas las figuras.

---

## Datos

Los datos de apertura de mesas y resultados por mesa provienen de las **actas digitales del STAE-ONPE**, disponibles públicamente en:
- `https://actas-stae.onpe.gob.pe/AIPRE{id}_STAE.pdf` (acta de instalación)
- `https://actas-stae.onpe.gob.pe/AEPRE{id}_STAE.pdf` (acta de escrutinio)

Los datos históricos de ausentismo (2006–2021) provienen del portal de datos abiertos de la ONPE.

---

## Citación

```
Rojas, M. (2026). Autopsia Electoral ONPE 2026: Impacto de las fallas logísticas
sobre el ausentismo y los resultados electorales en Lima. Repositorio público.
https://github.com/mathieurojas/autopsy_onpe2026
```

---

## Nota de transparencia

Todo el código es abierto. Todos los supuestos están documentados. Todos los datos fuente son públicos y verificables. El análisis se actualiza automáticamente conforme la ONPE publica nuevas actas.

Las verificaciones de robustez muestran que el resultado principal es positivo para RP **en todos los escenarios dentro del rango empíricamente calibrado** de preferencias de los votantes ausentes.

---

*Última actualización: pipeline ejecutado sobre 90.2% de mesas de sufragio de Lima y Callao.*
