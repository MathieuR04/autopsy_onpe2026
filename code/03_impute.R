# =============================================================================
# 03_impute.R
# Autopsia ONPE 2026 — Imputación contrafactual de votos
# =============================================================================
# Pregunta central: ¿cuántos votantes no pudieron votar por las demoras,
# y cómo habrían votado?
# =============================================================================

library(tidyverse)
library(fixest)

BASE  <- here::here()
CLEAN <- file.path(BASE, "data", "clean")
OUT   <- file.path(BASE, "output")

lima_2026  <- readRDS(file.path(CLEAN, "lima_2026_clean.rds"))
panel      <- readRDS(file.path(CLEAN, "panel.rds"))
grilla     <- readRDS(file.path(CLEAN, "grilla_predicciones.rds"))

# Necesitamos el modelo para generar predicciones contrafactuales
source(file.path(BASE, "code", "02_model.R"), local = TRUE)

TAMANO_MESA <- 300L

# =============================================================================
# PASO 1: Ausentismo contrafactual (si todas las mesas hubieran abierto a las 7am)
# =============================================================================
# Para cada mesa en Lima 2026, predecimos qué ausentismo habría tenido
# si su retraso fuera = 0 (apertura a tiempo).
# La diferencia con el ausentismo observado es el efecto atribuible al retraso.

lima_cf <- lima_2026 |>
  mutate(
    delay_min = 0L,          # contrafactual: todas abren a tiempo
    year_fct  = factor(2026) # requerido por fixest para predicción
  )

lima_2026 <- lima_2026 |>
  mutate(
    abs_observado    = absenteeism,
    abs_contrafactual = predict(modelo_principal, newdata = lima_cf),
    # Flooreamos en 0: el retraso no puede reducir ausentismo
    exceso_ausentismo = pmax(abs_observado - abs_contrafactual, 0),
    # Solo atribuimos exceso donde el efecto es estadísticamente significativo.
    # Los coeficientes del spline son significativos a partir del segmento 3,
    # que corresponde aproximadamente a retrasos >= 120 minutos (2 horas).
    # Por debajo de ese umbral, no podemos rechazar H0: efecto = 0.
    # Usar efectos no significativos inflaría artificialmente el estimado.
    exceso_ausentismo = if_else(delay_min >= 120, exceso_ausentismo, 0),
    # Votantes en exceso que no fueron: exceso de ausentismo × electores hábiles
    votantes_perdidos = round(exceso_ausentismo * eligible_voters)
  )

total_votantes_perdidos <- sum(lima_2026$votantes_perdidos)
cat("=== VOTANTES PERDIDOS POR RETRASO ===\n")
cat("Total Lima + Callao:", format(total_votantes_perdidos, big.mark = ","), "\n")

# Desglose por categoría de retraso
cat("\nDesglose por categoría de retraso:\n")
lima_2026 |>
  group_by(delay_cat) |>
  summarise(
    mesas              = n(),
    votantes_perdidos  = sum(votantes_perdidos),
    ausentismo_obs     = weighted.mean(abs_observado, eligible_voters),
    ausentismo_cf      = weighted.mean(abs_contrafactual, eligible_voters)
  ) |>
  print()

# Desglose por distrito (para mapa)
por_distrito <- lima_2026 |>
  group_by(district) |>
  summarise(
    mesas              = n(),
    votantes_perdidos  = sum(votantes_perdidos),
    delay_promedio     = weighted.mean(delay_min, eligible_voters),
    abs_observado      = weighted.mean(abs_observado, eligible_voters),
    abs_contrafactual  = weighted.mean(abs_contrafactual, eligible_voters),
    rp_share_obs       = weighted.mean(rp_share, total_voted, na.rm = TRUE),
    jpp_share_obs      = weighted.mean(jpp_share, total_voted, na.rm = TRUE)
  )

# =============================================================================
# PASO 2: Imputación de votos — escenario base (proporcional)
# =============================================================================
# Supuesto: los votantes perdidos habrían votado en la misma proporción
# que los votantes observados en su misma mesa.
# Este es el supuesto más conservador y directo.

lima_2026 <- lima_2026 |>
  mutate(
    votos_rp_imputados  = votantes_perdidos * rp_share,
    votos_jpp_imputados = votantes_perdidos * jpp_share
  )

total_rp_base  <- sum(lima_2026$votos_rp_imputados,  na.rm = TRUE)
total_jpp_base <- sum(lima_2026$votos_jpp_imputados, na.rm = TRUE)
diferencia_base <- total_rp_base - total_jpp_base

cat("\n=== IMPUTACIÓN BASE (proporcional) ===\n")
cat("Votos imputados RP:  ", format(round(total_rp_base),  big.mark = ","), "\n")
cat("Votos imputados JPP: ", format(round(total_jpp_base), big.mark = ","), "\n")
cat("Diferencia bruta:    ", format(round(diferencia_base), big.mark = ","),
    "(favorece a", ifelse(diferencia_base > 0, "RP", "JPP"), ")\n")

# =============================================================================
# PASO 3: Impacto sobre la brecha Lima
# =============================================================================
# Nota: NO hardcodeamos la brecha nacional porque el conteo sigue en curso.
# Reportamos solo el impacto atribuible (diferencia_base) que es independiente
# del conteo final. La brecha nacional se puede sumar externamente una vez
# que la ONPE publique resultados definitivos.

brecha_obs_lima <- sum(lima_2026$rp, na.rm = TRUE) - sum(lima_2026$jpp, na.rm = TRUE)

cat("\n=== IMPACTO ESTIMADO EN LIMA ===\n")
cat("Brecha RP-JPP observada en Lima (tablas scrapeadas):\n")
cat("  RP votos Lima:  ", format(sum(lima_2026$rp,  na.rm=TRUE), big.mark=","), "\n")
cat("  JPP votos Lima: ", format(sum(lima_2026$jpp, na.rm=TRUE), big.mark=","), "\n")
cat("  Brecha Lima:    ", format(brecha_obs_lima, big.mark=","), "\n\n")
cat("Votos imputados a favor de RP por fallas logísticas:\n")
cat("  Votos RP imputados:  ", format(round(total_rp_base),  big.mark=","), "\n")
cat("  Votos JPP imputados: ", format(round(total_jpp_base), big.mark=","), "\n")
cat("  Diferencia neta:     ", format(round(diferencia_base), big.mark=","),
    "(favorece a", ifelse(diferencia_base > 0, "RP", "JPP"), ")\n")
cat("\nNOTA: Sumar diferencia_base a la brecha nacional final de la ONPE\n")
cat("para obtener la brecha contrafactual completa.\n")

# Guardamos diferencia_base para uso externo
BRECHA_NACIONAL_ONPE <- NA_integer_  # se llenará con cifra final

# =============================================================================
# PASO 4: Guardar outputs para figura y robustez
# =============================================================================
saveRDS(lima_2026,   file.path(CLEAN, "lima_2026_imputado.rds"))
saveRDS(por_distrito, file.path(CLEAN, "por_distrito.rds"))

resumen_nacional <- tibble(
  escenario             = "Base (proporcional)",
  votantes_perdidos     = total_votantes_perdidos,
  votos_rp_imputados    = round(total_rp_base),
  votos_jpp_imputados   = round(total_jpp_base),
  diferencia_imputable  = round(diferencia_base)
  # brecha_contrafactual = diferencia_imputable + brecha_nacional_final_onpe
)

write_csv(resumen_nacional, file.path(OUT, "tables", "resumen_imputation_base.csv"))
cat("\n✓ Imputación base guardada.\n")
cat("NOTA: Actualizar VOTOS_RP/JPP_NACIONAL_ONPE con el conteo final.\n")

# =============================================================================
# NÚMEROS CLAVE — archivo único leído por el sitio web y el paper
# Se sobreescribe en cada ejecución para mantener cifras actualizadas
# =============================================================================
numeros_clave <- tibble(
  pct_cobertura        = round(nrow(lima_2026) / 29266 * 100, 1),
  n_mesas              = nrow(lima_2026),
  n_mesas_esperadas    = 29266L,
  n_mesas_afectadas    = sum(lima_2026$delay_min >= 120, na.rm = TRUE),
  votantes_perdidos    = total_votantes_perdidos,
  votos_rp_imputados   = round(total_rp_base),
  votos_jpp_imputados  = round(total_jpp_base),
  diferencia_imputable = round(diferencia_base),
  fecha_actualizacion  = format(Sys.Date(), "%d/%m/%Y")
)

write_csv(numeros_clave,
          file.path(OUT, "tables", "numeros_clave.csv"))
cat("✓ Números clave guardados en output/tables/numeros_clave.csv\n")
print(numeros_clave)
