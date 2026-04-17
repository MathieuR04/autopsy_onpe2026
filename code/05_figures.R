# =============================================================================
# 05_figures.R
# Autopsia ONPE 2026 — Todas las figuras
# =============================================================================

library(tidyverse)
library(sf)
library(scales)
library(patchwork)
library(ggtext)

BASE  <- here::here()
CLEAN <- file.path(BASE, "data", "clean")
OUT   <- file.path(BASE, "output", "figures")
RAW   <- file.path(BASE, "data", "raw")
dir.create(OUT, showWarnings = FALSE)

lima_2026    <- readRDS(file.path(CLEAN, "lima_2026_imputado.rds"))
grilla       <- readRDS(file.path(CLEAN, "grilla_predicciones.rds"))
por_distrito <- readRDS(file.path(CLEAN, "por_distrito.rds"))
residuos_r1  <- readRDS(file.path(CLEAN, "residuos_robustez1.rds"))
resultados_r2 <- readRDS(file.path(CLEAN, "resultados_robustez2.rds"))
panel        <- readRDS(file.path(CLEAN, "panel.rds"))

# Paleta de colores institucional
COL_RP   <- "#003087"   # azul Renovación Popular
COL_JPP  <- "#E31E24"   # rojo Juntos por el Perú
COL_GRAY <- "#9E9E9E"
COL_WARN <- "#FF6B00"

tema_autopsia <- theme_minimal(base_size = 13) +
  theme(
    plot.title       = element_text(face = "bold", size = 15),
    plot.subtitle    = element_text(color = "gray40", size = 11),
    plot.caption     = element_text(color = "gray50", size = 9),
    panel.grid.minor = element_blank(),
    axis.title       = element_text(size = 11)
  )

# =============================================================================
# FIGURA 1: Distribución de tiempos de apertura (histograma + CDF)
# =============================================================================
p1a <- lima_2026 |>
  filter(delay_min >= 0, delay_min <= 420) |>
  ggplot(aes(x = delay_min)) +
  geom_histogram(binwidth = 15, fill = COL_RP, alpha = 0.7, color = "white") +
  geom_vline(xintercept = c(60, 120, 180), linetype = "dashed",
             color = COL_WARN, linewidth = 0.8) +
  scale_x_continuous(
    breaks = seq(0, 420, 60),
    labels = function(x) paste0(7 + x %/% 60, ":", sprintf("%02d", x %% 60))
  ) +
  labs(
    title    = "¿A qué hora abrieron las mesas?",
    subtitle = "Distribución de tiempos de apertura — Lima y Callao, 12 de abril 2026",
    x        = "Hora de apertura",
    y        = "Número de mesas",
    caption  = "Líneas naranjas: 8am, 9am y 10am (umbral de retraso grave)"
  ) +
  tema_autopsia

p1b <- lima_2026 |>
  filter(delay_min >= 0, delay_min <= 420) |>
  ggplot(aes(x = delay_min)) +
  stat_ecdf(color = COL_RP, linewidth = 1.2) +
  geom_vline(xintercept = c(60, 120, 180), linetype = "dashed",
             color = COL_WARN, linewidth = 0.8) +
  scale_x_continuous(
    breaks = seq(0, 420, 60),
    labels = function(x) paste0(7 + x %/% 60, ":", sprintf("%02d", x %% 60))
  ) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title    = "Proporción acumulada de mesas abiertas",
    subtitle = "¿Cuántas mesas ya estaban abiertas a cada hora?",
    x        = "Hora de apertura",
    y        = "% de mesas ya instaladas",
    caption  = " "
  ) +
  tema_autopsia

fig1 <- p1a + p1b +
  plot_annotation(
    title   = "Retrasos en la apertura de mesas",
    caption = "Fuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  )

ggsave(file.path(OUT, "fig1_distribucion_apertura.png"),
       fig1, width = 14, height = 6, dpi = 300)
cat("✓ Figura 1 guardada\n")

# =============================================================================
# FIGURA 2: Curva de respuesta — retraso → ausentismo (modelo principal)
# =============================================================================
fig2 <- grilla |>
  ggplot(aes(x = delay_min, y = efecto_marginal)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi),
              fill = COL_RP, alpha = 0.15) +
  geom_line(color = COL_RP, linewidth = 1.4) +
  geom_vline(xintercept = c(60, 120, 180), linetype = "dashed",
             color = COL_WARN, linewidth = 0.7) +
  geom_hline(yintercept = 0, color = "gray40") +
  scale_x_continuous(
    breaks = seq(0, 420, 60),
    labels = function(x) paste0(7 + x %/% 60, ":", sprintf("%02d", x %% 60))
  ) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  annotate("text", x = 65, y = max(grilla$efecto_marginal) * 0.5,
           label = "1 hora\nde retraso", size = 3.2, hjust = 0, color = COL_WARN) +
  annotate("text", x = 185, y = max(grilla$efecto_marginal) * 0.7,
           label = "3 horas\nde retraso", size = 3.2, hjust = 0, color = COL_WARN) +
  labs(
    title    = "¿Cuánto aumenta el ausentismo según la hora de apertura?",
    subtitle = "Efecto marginal sobre la tasa de ausentismo respecto a una mesa abierta a las 7:00 am",
    x        = "Hora de apertura de la mesa",
    y        = "Aumento en ausentismo",
    caption  = "Spline cúbico restringido. Banda: IC 95%. Errores estándar clusterizados por distrito.\nFuente: Actas ONPE 2026, datos históricos 2006–2021 | Autopsia Electoral ONPE 2026"
  ) +
  tema_autopsia

ggsave(file.path(OUT, "fig2_curva_respuesta.png"),
       fig2, width = 12, height = 6, dpi = 300)
cat("✓ Figura 2 guardada\n")

# =============================================================================
# FIGURA 3: Ausentismo observado vs. contrafactual por bin de retraso
# =============================================================================
fig3 <- lima_2026 |>
  group_by(delay_cat) |>
  summarise(
    abs_obs = weighted.mean(abs_observado,     eligible_voters),
    abs_cf  = weighted.mean(abs_contrafactual, eligible_voters),
    n       = n()
  ) |>
  pivot_longer(c(abs_obs, abs_cf), names_to = "tipo", values_to = "ausentismo") |>
  mutate(tipo = recode(tipo,
    "abs_obs" = "Observado (con retraso)",
    "abs_cf"  = "Contrafactual (sin retraso)"
  )) |>
  ggplot(aes(x = delay_cat, y = ausentismo, fill = tipo)) +
  geom_col(position = "dodge", alpha = 0.85) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(values = c("Observado (con retraso)" = COL_RP,
                                "Contrafactual (sin retraso)" = COL_GRAY)) +
  labs(
    title    = "Ausentismo observado vs. contrafactual",
    subtitle = "¿Cuánto mayor fue el ausentismo de lo que habría sido sin retraso?",
    x        = "Categoría de retraso",
    y        = "Tasa de ausentismo promedio",
    fill     = NULL,
    caption  = "Fuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  tema_autopsia +
  theme(legend.position = "top", axis.text.x = element_text(angle = 15, hjust = 1))

ggsave(file.path(OUT, "fig3_ausentismo_obs_vs_cf.png"),
       fig3, width = 12, height = 6, dpi = 300)
cat("✓ Figura 3 guardada\n")

# =============================================================================
# FIGURA 4: Robustez 1 — Variación dentro del distrito (estudio de evento)
# =============================================================================
fig4 <- residuos_r1 |>
  ggplot(aes(x = delay_cat, y = abs_residual_m)) +
  geom_col(fill = COL_RP, alpha = 0.8) +
  geom_errorbar(
    aes(ymin = abs_residual_m - 1.96 * abs_residual_se,
        ymax = abs_residual_m + 1.96 * abs_residual_se),
    width = 0.3, color = "gray30"
  ) +
  geom_hline(yintercept = 0, color = "gray40") +
  scale_y_continuous(labels = percent_format(accuracy = 0.5)) +
  labs(
    title    = "Variación dentro del distrito (robustez)",
    subtitle = "Ausentismo residual por categoría de retraso, luego de restar la media del distrito",
    x        = "Categoría de retraso",
    y        = "Ausentismo residual (demeaned por distrito)",
    caption  = "Barras de error: IC 95%.\nFuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  tema_autopsia +
  theme(axis.text.x = element_text(angle = 15, hjust = 1))

ggsave(file.path(OUT, "fig4_robustez_dentro_distrito.png"),
       fig4, width = 11, height = 6, dpi = 300)
cat("✓ Figura 4 guardada\n")

# =============================================================================
# FIGURA 5: Robustez 2 — Sensibilidad de la brecha según preferencia no-votantes
# =============================================================================
# Valor base (delta = 0): votos netos imputados a RP en escenario proporcional
# Este número proviene directamente de 03_impute.R (diferencia_base)
# No incluye brecha nacional — reportamos solo el impacto atribuible
base_val <- resultados_r2$brecha_contrafactual[which.min(abs(resultados_r2$delta))]
y_max    <- max(resultados_r2$brecha_contrafactual)
y_min    <- min(resultados_r2$brecha_contrafactual)
y_rango  <- y_max - y_min

fig5 <- resultados_r2 |>
  ggplot(aes(x = delta, y = brecha_contrafactual)) +
  geom_ribbon(aes(ymin = 0, ymax = brecha_contrafactual),
              fill = COL_RP, alpha = 0.12) +
  geom_line(color = COL_RP, linewidth = 1.3) +
  geom_hline(yintercept = 0, linetype = "solid", color = "black", linewidth = 0.8) +
  geom_hline(yintercept = base_val, linetype = "dashed", color = "gray50") +
  geom_point(data = resultados_r2 |> filter(delta == 0),
             aes(x = delta, y = brecha_contrafactual),
             color = COL_RP, size = 3) +
  # Anotación escenario base — debajo de la línea punteada para no solapar
  annotate("text", x = -0.028, y = base_val - y_rango * 0.07,
           label = "Escenario base
(proporcional)",
           hjust = 0, size = 3.2, color = "gray40") +
  # Zonas de color
  annotate("rect", xmin = 0, xmax = 0.03, ymin = -Inf, ymax = Inf,
           fill = COL_JPP, alpha = 0.04) +
  annotate("rect", xmin = -0.03, xmax = 0, ymin = -Inf, ymax = Inf,
           fill = COL_RP, alpha = 0.04) +
  # Etiquetas de zona — en la parte inferior para no solapar con la curva
  annotate("text", x = 0.015, y = y_min + y_rango * 0.12,
           label = "Ausentes más
favorables a JPP
(conservador para RP)",
           size = 2.8, color = COL_JPP, lineheight = 0.9) +
  annotate("text", x = -0.015, y = y_min + y_rango * 0.12,
           label = "Ausentes más
favorables a RP
(escenario optimista)",
           size = 2.8, color = COL_RP, lineheight = 0.9) +
  scale_x_continuous(
    breaks = seq(-0.03, 0.03, by = 0.01),
    labels = function(x) paste0(ifelse(x > 0, "+", ""), round(x * 100, 0), "pp")
  ) +
  scale_y_continuous(labels = comma_format()) +
  labs(
    title    = "Sensibilidad de la brecha RP-JPP según preferencia de los votantes ausentes",
    subtitle = "Votos netos imputados a RP bajo distintos supuestos sobre las preferencias de quienes no pudieron votar",
    x        = "Desviación de preferencia de los ausentes respecto a votantes observados en su misma mesa",
    y        = "Votos netos imputados a favor de RP",
    caption  = "Línea punteada = escenario base (proporcional). Línea sólida en 0 = sin efecto neto.\nRango calibrado a ±2 desviaciones estándar de la variación entre mesas del mismo distrito.\nFuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  tema_autopsia

ggsave(file.path(OUT, "fig5_robustez_sensibilidad.png"),
       fig5, width = 12, height = 6, dpi = 300)
cat("✓ Figura 5 guardada\n")

# =============================================================================
# FIGURAS 6–8: MAPAS
# =============================================================================
shp <- st_read(file.path(RAW, "Limite_Distrital_INEI_2025_CPV.shp"), quiet = TRUE)

# Filtrar solo Lima y Callao
# Función para normalizar nombres de distrito (manejo de encoding de Ñ)
normalizar_distrito <- function(x) {
  x |>
    stringr::str_replace_all("Ã|Ã±|Ñ|ñ", "Ñ") |>
    stringr::str_replace_all("BRE.A", "BREÑA") |>
    stringr::str_to_upper() |>
    stringr::str_trim()
}

shp_lim <- shp |>
  filter(PROVINCIA %in% c("LIMA", "CALLAO")) |>
  mutate(
    district = normalizar_distrito(DISTRITO),
    # Corregir guión en Carmen de la Legua
    district = if_else(
      district == "CARMEN DE LA LEGUA REYNOSO",
      "CARMEN DE LA LEGUA-REYNOSO",
      district
    )
  )

# Merge con datos por distrito
# Normalizar district en por_distrito antes del merge
por_distrito <- por_distrito |>
  mutate(district = normalizar_distrito(district))

mapa_data <- shp_lim |>
  left_join(por_distrito, by = "district")

# FIGURA 6: Retraso promedio por distrito
fig6 <- ggplot(mapa_data) +
  geom_sf(aes(fill = delay_promedio), color = "white", linewidth = 0.3) +
  scale_fill_gradient2(
    low      = "#2166AC",
    mid      = "#F7F7F7",
    high     = "#D73027",
    midpoint = 60,
    na.value = "gray90",
    name     = "Minutos\nde retraso",
    labels   = function(x) paste0(x, " min")
  ) +
  labs(
    title    = "Retraso promedio en apertura de mesas por distrito",
    subtitle = "Lima Metropolitana y Callao — Elecciones Generales 2026",
    caption  = "Fuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40"),
    legend.position = "right"
  )

ggsave(file.path(OUT, "fig6_mapa_retraso.png"),
       fig6, width = 10, height = 10, dpi = 300)
cat("✓ Figura 6 guardada\n")

# FIGURA 7: Votantes perdidos por distrito
fig7 <- ggplot(mapa_data) +
  geom_sf(aes(fill = votantes_perdidos), color = "white", linewidth = 0.3) +
  scale_fill_gradient(
    low      = "#FFF5EB",
    high     = "#D94801",
    na.value = "gray90",
    name     = "Votantes\nperdidos",
    labels   = comma_format()
  ) +
  labs(
    title    = "Votantes que no pudieron sufragar por distrito",
    subtitle = "Lima Metropolitana y Callao — Elecciones Generales 2026",
    caption  = "Fuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40"),
    legend.position = "right"
  )

ggsave(file.path(OUT, "fig7_mapa_votantes_perdidos.png"),
       fig7, width = 10, height = 10, dpi = 300)
cat("✓ Figura 7 guardada\n")

# FIGURA 8: Share de RP por distrito (contexto político)
fig8 <- ggplot(mapa_data) +
  geom_sf(aes(fill = rp_share_obs), color = "white", linewidth = 0.3) +
  scale_fill_gradient2(
    low      = COL_JPP,
    mid      = "#F7F7F7",
    high     = COL_RP,
    midpoint = 0.12,
    na.value = "gray90",
    name     = "Proporción\nRP",
    labels   = percent_format(accuracy = 1)
  ) +
  labs(
    title    = "Fortaleza electoral de RP (Renovación Popular) por distrito",
    subtitle = "Lima Metropolitana y Callao — Elecciones Generales 2026",
    caption  = "Azul = mayor concentración de votos RP. Rojo = mayor concentración de votos JPP.\nFuente: Actas ONPE 2026 | Autopsia Electoral ONPE 2026"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40"),
    legend.position = "right"
  )

ggsave(file.path(OUT, "fig8_mapa_rp_share.png"),
       fig8, width = 10, height = 10, dpi = 300)
cat("✓ Figura 8 guardada\n")

# =============================================================================
# FIGURA 9: Mesas faltantes por distrito
# (correlación visual entre zonas sin datos y zonas con más retrasos)
# =============================================================================
cobertura <- read_csv(file.path(BASE, "data", "clean", "cobertura_distritos.csv"),
                      show_col_types = FALSE) |>
  mutate(district = str_to_upper(str_trim(district)))

cobertura <- cobertura |>
  mutate(district = normalizar_distrito(district))

mapa_cobertura <- shp_lim |>
  left_join(cobertura, by = "district") |>
  mutate(
    pct_faltante = 1 - replace_na(pct_cov, 0),
    # Si no hay datos en absoluto, marcar como 100% faltante
    pct_faltante = if_else(is.na(pct_cov), 1, pct_faltante)
  )

fig9 <- ggplot(mapa_cobertura) +
  geom_sf(aes(fill = pct_faltante), color = "white", linewidth = 0.3) +
  scale_fill_gradient(
    low      = "#F0F9E8",
    high     = "#08589E",
    na.value = "gray90",
    name     = "% actas
faltantes",
    labels   = percent_format(accuracy = 1)
  ) +
  labs(
    title    = "Actas aún no disponibles por distrito",
    subtitle = "Los distritos con más actas faltantes coinciden con las zonas de mayores retrasos",
    caption  = "Fuente: Actas ONPE 2026 scrapeadas vs. total esperado por distrito | Autopsia Electoral ONPE 2026"
  ) +
  theme_void(base_size = 12) +
  theme(
    plot.title      = element_text(face = "bold", size = 14),
    plot.subtitle   = element_text(color = "gray40"),
    legend.position = "right"
  )

ggsave(file.path(OUT, "fig9_mapa_actas_faltantes.png"),
       fig9, width = 10, height = 10, dpi = 300)
cat("✓ Figura 9 guardada\n")

cat("\n✓ Todas las figuras guardadas en output/figures/\n")
cat("NOTA: Re-ejecutar cuando se actualice lima_2026.csv con nuevas tablas.\n")
