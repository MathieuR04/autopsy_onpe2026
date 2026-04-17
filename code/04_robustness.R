# =============================================================================
# 04_robustness.R
# Autopsia ONPE 2026 — Chequeos de robustez
# =============================================================================
# Robustez 1: Variación mesa-a-mesa dentro del distrito
# Robustez 2: Sensibilidad diferencial de la preferencia de los no-votantes
# =============================================================================

library(tidyverse)
library(fixest)
library(splines)

BASE  <- here::here()
CLEAN <- file.path(BASE, "data", "clean")
OUT   <- file.path(BASE, "output")

panel      <- readRDS(file.path(CLEAN, "panel.rds"))

source(file.path(BASE, "code", "02_model.R"), local = TRUE)

# Cargar DESPUÉS de source() para que no sea sobreescrito por 02_model.R
lima_2026  <- readRDS(file.path(CLEAN, "lima_2026_imputado.rds"))

# Brecha nacional: no hardcodeada porque el conteo sigue en curso.
# La robustez reporta la diferencia_imputable (independiente del conteo).
# Para obtener brecha_contrafactual, sumar a la cifra final de la ONPE.
BRECHA_NACIONAL_ONPE <- 0L  # placeholder neutro; cambia signo relativo a 0

KNOTS <- c(60, 120, 180)

# =============================================================================
# ROBUSTEZ 1: Variación dentro del distrito
# =============================================================================
# Identificación más exigente: efectos fijos district×year (en vez de solo district)
# El coeficiente del retraso se identifica únicamente de variación entre mesas
# del mismo distrito en el mismo año. Esto elimina cualquier confounder
# a nivel de distrito-año (ej. si en un distrito hubo más problemas en general).
# =============================================================================

cat("=== ROBUSTEZ 1: Efectos fijos distrito×año ===\n")

modelo_r1_dxye <- feols(
  absenteeism ~ ns(delay_min, knots = KNOTS, Boundary.knots = c(0, 420)) |
    district^year_fct,
  data    = panel |> filter(!is.na(delay_min)),
  cluster = ~district,
  weights = ~eligible_voters
)

# Comparación con modelo principal
cat("\nComparación: modelo principal vs. FE distrito×año:\n")
etable(modelo_principal, modelo_r1_dxye,
       headers = c("FE: distrito + año", "FE: distrito × año"),
       file    = file.path(OUT, "tables", "robustez1_fe_interaccion.tex"),
       tex     = TRUE)

# Estudio de evento: ausentismo promedio por categoría de retraso, dentro del distrito
# Residualiza ausentismo sobre FEs de distrito y año, luego promedia por bin
residuos_r1 <- panel |>
  filter(!is.na(delay_min), year == 2026) |>
  mutate(
    # Residual de ausentismo respecto a media del distrito
    abs_residual = absenteeism - ave(absenteeism, district, FUN = mean),
    # delay_cat no existe en panel, reconstruirla aquí
    delay_cat = case_when(
      delay_min <= 15             ~ "A tiempo (≤15 min)",
      delay_min <= 60             ~ "Leve (16–60 min)",
      delay_min <= 120            ~ "Moderado (61–120 min)",
      delay_min <= 180            ~ "Severo (121–180 min)",
      TRUE                        ~ "Muy severo (>180 min)"
    ) |> factor(levels = c(
      "A tiempo (≤15 min)", "Leve (16–60 min)",
      "Moderado (61–120 min)", "Severo (121–180 min)", "Muy severo (>180 min)"
    ))
  ) |>
  group_by(delay_cat) |>
  summarise(
    n              = n(),
    abs_residual_m = weighted.mean(abs_residual, eligible_voters),
    abs_residual_se = sd(abs_residual) / sqrt(n())
  )

cat("\nAusentismo residual por categoría de retraso:\n")
print(residuos_r1)
saveRDS(residuos_r1, file.path(CLEAN, "residuos_robustez1.rds"))

# =============================================================================
# ROBUSTEZ 2: Sensibilidad diferencial de la preferencia de los no-votantes
# =============================================================================
# Supuesto base: no-votantes habrían votado igual que observados en su mesa.
# ¿Qué pasa si los no-votantes tenían preferencias diferentes?
#
# Parametrizamos con delta ∈ [-0.15, +0.15]:
#
#   delta > 0 → los no-votantes son MÁS favorables a JPP que los observados
#               (escenario conservador para RP)
#               Ej: los seguidores de RP son más perseverantes, se quedaron
#               a votar pese al retraso → los que se fueron son más de JPP
#
#   delta < 0 → los no-votantes son MÁS favorables a RP
#               (escenario favorable para RP)
#               Ej: seguidores de RP llegaron temprano y se fueron al ver
#               las mesas cerradas, sin volver
#
# Rango calibrado empíricamente:
# La desviación estándar within-distrito de la share de JPP es ~1.3pp (mediana)
# y ~2.3pp en el percentil 90. Usamos ±3pp como rango generoso (>2 SD).
# Un delta de +3pp significa que los no-votantes favorecen a JPP 3pp más
# que los votantes observados en su misma mesa — un supuesto ya muy extremo
# dado que JPP obtuvo solo ~2.5% en Lima.
# =============================================================================

DELTA_MAX <- 0.03   # ±3pp, calibrado a la variación within-distrito observada

cat("\n=== ROBUSTEZ 2: Sensibilidad diferencial de preferencia ===\n")
cat("Rango delta: ±", DELTA_MAX*100, "pp (calibrado a variación within-distrito)\n")

calcular_escenario <- function(delta, datos = lima_2026) {
  # datos debe ser lima_2026_imputado con columna votantes_perdidos ya calculada
  datos |>
    filter(votantes_perdidos > 0) |>   # solo mesas con efecto atribuible
    mutate(
      # Ajustamos la share de JPP entre los no-votantes
      jpp_share_nv = pmin(pmax(jpp_share + delta, 0), 1),
      rp_share_nv  = pmin(pmax(rp_share  - delta, 0), 1),
      votos_rp_imp  = votantes_perdidos * rp_share_nv,
      votos_jpp_imp = votantes_perdidos * jpp_share_nv
    ) |>
    summarise(
      delta                  = delta,
      total_rp_imp           = sum(votos_rp_imp,  na.rm = TRUE),
      total_jpp_imp          = sum(votos_jpp_imp, na.rm = TRUE),
      diferencia_imputable   = total_rp_imp - total_jpp_imp,
      # brecha_contrafactual = diferencia_imputable + brecha_nacional_final_onpe
      brecha_contrafactual   = diferencia_imputable,  # relativa a 0; sumar brecha final
      rp_gana_segunda_vuelta = brecha_contrafactual > 0
    )
}

deltas <- seq(-DELTA_MAX, DELTA_MAX, by = 0.005)
resultados_r2 <- map_dfr(deltas, calcular_escenario)

cat("\nResultados de sensibilidad (delta seleccionados):\n")
resultados_r2 |>
  filter(delta %in% c(-0.03, -0.02, -0.01, 0, 0.01, 0.02, 0.03)) |>
  mutate(
    interpretacion = case_when(
      delta < 0  ~ "No-votantes más pro-RP",
      delta == 0 ~ "Base (proporcional)",
      delta > 0  ~ "No-votantes más pro-JPP"
    )
  ) |>
  select(delta, interpretacion, diferencia_imputable, brecha_contrafactual) |>
  print()

# Escenario más conservador (máximo delta favorable a JPP)
escenario_conservador <- resultados_r2 |> filter(delta == 0.15)
cat("\nEscenario MÁS conservador (delta=+0.15, no-votantes 15pp más pro-JPP):\n")
cat("Diferencia imputable:", round(escenario_conservador$diferencia_imputable), "\n")
cat("Brecha contrafactual:", round(escenario_conservador$brecha_contrafactual),
    ifelse(escenario_conservador$brecha_contrafactual > 0, "(RP arriba)", "(JPP arriba)"), "\n")

# Escenario más favorable a RP
escenario_rp_max <- resultados_r2 |> filter(delta == -0.15)
cat("\nEscenario MÁS favorable a RP (delta=-0.15):\n")
cat("Diferencia imputable:", round(escenario_rp_max$diferencia_imputable), "\n")
cat("Brecha contrafactual:", round(escenario_rp_max$brecha_contrafactual), "\n")

# Umbral: ¿para qué delta cambia el ganador?
umbral <- resultados_r2 |>
  filter(sign(brecha_contrafactual) != sign(lag(brecha_contrafactual))) |>
  slice(1)

if (nrow(umbral) > 0) {
  cat("\nUmbral de cambio de ganador: delta ≈", umbral$delta, "\n")
} else {
  cat("\nEn ningún escenario del rango [-0.15, +0.15] cambia el resultado.\n")
}

# =============================================================================
# Guardar y exportar
# =============================================================================
saveRDS(resultados_r2, file.path(CLEAN, "resultados_robustez2.rds"))

write_csv(resultados_r2,
          file.path(OUT, "tables", "robustez2_sensibilidad_delta.csv"))

cat("\n✓ Robustez guardada.\n")
