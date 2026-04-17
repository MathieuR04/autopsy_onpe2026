# =============================================================================
# 02_model.R
# Autopsia ONPE 2026 — Modelo principal: efecto del retraso en ausentismo
# =============================================================================
# Modelo: spline cúbico restringido + efectos fijos distrito × año
# La variación identificante viene de las mesas de Lima 2026.
# Los datos históricos solo sirven para fijar los efectos fijos de distrito.
# =============================================================================

library(tidyverse)
library(fixest)
library(splines)

BASE  <- here::here()
CLEAN <- file.path(BASE, "data", "clean")
OUT   <- file.path(BASE, "output")
dir.create(file.path(OUT, "tables"),  showWarnings = FALSE)
dir.create(file.path(OUT, "figures"), showWarnings = FALSE)

panel    <- readRDS(file.path(CLEAN, "panel.rds"))
lima_2026 <- readRDS(file.path(CLEAN, "lima_2026_clean.rds"))

# =============================================================================
# NOTA METODOLÓGICA — ¿Por qué efectos fijos de distrito?
# =============================================================================
# Cada distrito tiene un nivel de ausentismo "estructural" que refleja su
# cultura política, distancia a locales, composición demográfica, etc.
# Los efectos fijos absorben todo eso. Lo que nos queda es la variación
# dentro del distrito: mesas que abrieron tarde vs. a tiempo, que es
# causada por el shock logístico de Galaga (exógeno al nivel de ausentismo).
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Definir nudos del spline
# -----------------------------------------------------------------------------
# Basados en la distribución empírica del retraso:
# - Percentil 25 ≈ 12 min (mayoría abrió a tiempo o casi)
# - Percentil 75 ≈ 70 min
# - Percentil 90 ≈ 120 min
# Los nudos marcan donde esperamos cambios en la pendiente:
#   60 min  → empieza a ser retraso serio (ventana de voto < 9h)
#   120 min → muy severo (ventana < 8h, votantes probablemente ya se fueron)
#   180 min → extremo (ventana < 7h)
KNOTS <- c(60, 120, 180)

# -----------------------------------------------------------------------------
# 2. Modelo principal
# -----------------------------------------------------------------------------
# Solo usamos las observaciones con delay_min no-NA para el término de retraso
# (i.e., mesas Lima 2026). Todas las observaciones históricas contribuyen
# a identificar los efectos fijos de distrito y año.

modelo_principal <- feols(
  absenteeism ~ ns(delay_min, knots = KNOTS, Boundary.knots = c(0, 420)) |
    district + year_fct,
  data    = panel |> filter(!is.na(delay_min)),
  cluster = ~district,
  weights = ~eligible_voters   # ponderar por tamaño de mesa
)

cat("=== MODELO PRINCIPAL ===\n")
print(summary(modelo_principal))

etable(
  modelo_principal,
  file      = file.path(OUT, "tables", "tabla_modelo_principal.tex"),
  title     = "Efecto del retraso en apertura de mesa sobre ausentismo",
  notes     = "Errores estándar clusterizados por distrito. Spline cúbico restringido con nudos en 60, 120 y 180 minutos. Efectos fijos de distrito y año.",
  tex       = TRUE
)

# -----------------------------------------------------------------------------
# 3. Modelos alternativos (para robustez de especificación)
# -----------------------------------------------------------------------------
# M2: sin ponderar
modelo_nopesos <- feols(
  absenteeism ~ ns(delay_min, knots = KNOTS, Boundary.knots = c(0, 420)) |
    district + year_fct,
  data    = panel |> filter(!is.na(delay_min)),
  cluster = ~district
)

# M3: nudos alternativos (más conservador, menos flexible)
modelo_knots_alt <- feols(
  absenteeism ~ ns(delay_min, knots = c(90, 180), Boundary.knots = c(0, 420)) |
    district + year_fct,
  data    = panel |> filter(!is.na(delay_min)),
  cluster = ~district,
  weights = ~eligible_voters
)

# M4: solo 2026 Lima, sin datos históricos (como placebo)
# Si el efecto desaparece al quitar FEs identificados históricamente,
# indica que la variación dentro de distritos es la que importa
modelo_solo2026 <- feols(
  absenteeism ~ ns(delay_min, knots = KNOTS, Boundary.knots = c(0, 420)) |
    district,
  data    = lima_2026,
  cluster = ~district,
  weights = ~eligible_voters
)

cat("\n=== COMPARACIÓN DE ESPECIFICACIONES ===\n")
etable(modelo_principal, modelo_nopesos, modelo_knots_alt, modelo_solo2026,
       headers = c("Principal", "Sin pesos", "Nudos alt.", "Solo 2026"))

# -----------------------------------------------------------------------------
# 4. Curva de respuesta: retraso → ausentismo
# -----------------------------------------------------------------------------
# Construimos una grilla de delay_min = 0 a 420 (7am a 2pm)
# y predecimos el efecto marginal sobre ausentismo

# fixest no permite SEs en predicciones con FEs absorbidos.
# Estrategia: predecimos el efecto marginal como diferencia entre
# predict(delay=d) - predict(delay=0), usando el mismo distrito de referencia.
# Los ICs se obtienen por bootstrap sobre los residuos del spline.

distrito_ref <- "SAN BORJA"

delay_seq <- seq(0, 420, by = 5)

grilla <- tibble(
  delay_min = delay_seq,
  district  = distrito_ref,
  year_fct  = factor(2026)
)

grilla_cf <- grilla |> mutate(delay_min = 0L)

# Predicciones puntuales (FEs cancelan en la diferencia)
pred_obs <- predict(modelo_principal, newdata = grilla)
pred_base <- predict(modelo_principal, newdata = grilla_cf)

grilla <- grilla |>
  mutate(
    pred_abs        = pred_obs,
    efecto_marginal = pred_obs - pred_base,
    hora_label      = paste0(7 + delay_min %/% 60, ":",
                             sprintf("%02d", delay_min %% 60))
  )

# Bootstrap IC: re-muestreamos distritos (cluster bootstrap)
set.seed(42)
B          <- 200
distritos  <- unique(panel$district[panel$year == 2026 & !is.na(panel$delay_min)])
boot_efecto <- matrix(NA_real_, nrow = length(delay_seq), ncol = B)

for (b in seq_len(B)) {
  muestra_d <- sample(distritos, length(distritos), replace = TRUE)
  boot_data <- map_dfr(muestra_d, ~panel[panel$district == .x & !is.na(panel$delay_min), ])
  tryCatch({
    m_boot <- feols(
      absenteeism ~ ns(delay_min, knots = KNOTS, Boundary.knots = c(0, 420)) |
        district + year_fct,
      data    = boot_data,
      weights = ~eligible_voters,
      warn    = FALSE, notes = FALSE
    )
    p_obs  <- predict(m_boot, newdata = grilla)
    p_base <- predict(m_boot, newdata = grilla_cf)
    boot_efecto[, b] <- p_obs - p_base
  }, error = function(e) NULL)
}

grilla <- grilla |>
  mutate(
    ci_lo = apply(boot_efecto, 1, quantile, probs = 0.025, na.rm = TRUE),
    ci_hi = apply(boot_efecto, 1, quantile, probs = 0.975, na.rm = TRUE)
  )

saveRDS(grilla, file.path(CLEAN, "grilla_predicciones.rds"))

# Tabla resumen de efectos en horas clave
horas_clave <- grilla |>
  filter(delay_min %in% c(0, 30, 60, 90, 120, 150, 180, 240, 300, 360, 420)) |>
  select(hora_label, pred_abs, efecto_marginal, ci_lo, ci_hi)

cat("\n=== EFECTOS MARGINALES EN HORAS CLAVE ===\n")
print(horas_clave)

write_csv(horas_clave, file.path(OUT, "tables", "efectos_marginales.csv"))

cat("\n✓ Modelos guardados.\n")
