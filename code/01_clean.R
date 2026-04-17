# =============================================================================
# 01_clean.R
# Autopsia ONPE 2026 — Limpieza y construcción del panel
# =============================================================================
# Inputs:  data/raw/lima_2026.csv, lima_2006.csv, lima_2011.csv,
#          lima_2016.csv, lima_2021.csv, districts.csv
# Outputs: data/clean/panel.rds, data/clean/lima_2026_clean.rds
# =============================================================================

library(tidyverse)
library(lubridate)
library(janitor)

BASE <- here::here()   # raíz del proyecto autopsy_onpe2026/
RAW  <- file.path(BASE, "data", "raw")
CLEAN <- file.path(BASE, "data", "clean")
dir.create(CLEAN, showWarnings = FALSE)

# Función para normalizar el nombre de Breña independientemente del encoding
# El problema: BREÑA aparece con bytes distintos en diferentes archivos
normalizar_distrito <- function(x) {
  x |>
    str_replace_all("Ã|Ã±|Ñ|ñ", "Ñ") |>
    str_replace_all("BRE.A", "BREÑA") |>
    str_to_upper() |>
    str_trim()
}

# -----------------------------------------------------------------------------
# 1. Cargar datos 2026
# -----------------------------------------------------------------------------
lima_2026_raw <- read_csv(
  file.path(RAW, "lima_2026.csv"),
  locale = locale(encoding = "latin1")
)

# Parsear installation_time → minutos de retraso desde las 7:00 am
parse_delay <- function(time_str) {
  # Formato: "09:16 a. m." o "02:14 p. m."
  time_str <- str_trim(time_str)
  
  hour   <- as.integer(str_extract(time_str, "^\\d+"))
  minute <- as.integer(str_extract(time_str, "(?<=:)\\d+"))
  is_pm  <- str_detect(time_str, "p\\. m\\.")
  
  # Convertir a horas en escala de 24h
  hour_24 <- case_when(
    is_pm  & hour != 12 ~ hour + 12L,
    !is_pm & hour == 12 ~ 0L,
    TRUE                ~ hour
  )
  
  total_minutes <- hour_24 * 60L + minute
  delay <- total_minutes - (7L * 60L)   # minutos desde las 7:00 am
  delay
}

lima_2026 <- lima_2026_raw |>
  mutate(
    year          = 2026L,
    absenteeism   = 1 - (total_voted / eligible_voters),
    delay_min     = parse_delay(installation_time),
    # Tabla abierta antes de las 7am → retraso = 0 (llegó material previo)
    delay_min     = pmax(delay_min, 0L),
    # Outliers: retrasos > 7 horas son imposibles (cierre a 6pm = 660 min max)
    delay_min     = pmin(delay_min, 660L),
    # Bins de severidad de retraso (para análisis descriptivo y robustez)
    delay_cat = case_when(
      delay_min <= 15             ~ "A tiempo (≤15 min)",
      delay_min <= 60             ~ "Leve (16–60 min)",
      delay_min <= 120            ~ "Moderado (61–120 min)",
      delay_min <= 180            ~ "Severo (121–180 min)",
      TRUE                        ~ "Muy severo (>180 min)"
    ) |> factor(levels = c(
      "A tiempo (≤15 min)", "Leve (16–60 min)",
      "Moderado (61–120 min)", "Severo (121–180 min)", "Muy severo (>180 min)"
    )),
    # Indicador: mesa afectada por el shock logístico
    affected      = delay_min > 30,
    rp_share      = rp / total_voted,
    jpp_share     = jpp / total_voted,
    margin_rp_jpp = rp_share - jpp_share
  ) |>
  # Normalizar nombres de distrito — manejo especial de Breña por problemas de encoding
  mutate(
    district_clean = normalizar_distrito(district)
  )

cat("=== 2026: distribución de retraso ===\n")
print(summary(lima_2026$delay_min))
cat("\nTablas por categoría de retraso:\n")
print(count(lima_2026, delay_cat))
cat("\nTablas con retraso > 60 min:", sum(lima_2026$delay_min > 60), "\n")
cat("Tablas con retraso > 120 min:", sum(lima_2026$delay_min > 120), "\n")
cat("Tablas con retraso > 180 min:", sum(lima_2026$delay_min > 180), "\n")

# Alerta: tablas aún faltantes vs esperadas
districts_ref <- read_csv(
  file.path(RAW, "districts.csv"),
  locale = locale(encoding = "latin1")
) |>
  mutate(polling_tables = as.integer(str_remove_all(as.character(polling_tables), ",")))

cobertura <- lima_2026 |>
  count(district = district_clean, name = "got") |>
  right_join(
    districts_ref |> mutate(district = str_to_upper(district)),
    by = "district"
  ) |>
  mutate(
    got     = replace_na(got, 0L),
    missing = polling_tables - got,
    pct_cov = got / polling_tables
  ) |>
  arrange(desc(missing))

cat("\n=== COBERTURA POR DISTRITO (tablas faltantes) ===\n")
print(cobertura)
cat("\nTotal cubierto:", sum(cobertura$got),
    "/ Total esperado:", sum(cobertura$polling_tables),
    "/ Faltantes:", sum(cobertura$missing), "\n")

# NOTA: Este script debe re-ejecutarse cada vez que se actualice lima_2026.csv
# con nuevas tablas del scraper.

# -----------------------------------------------------------------------------
# 2. Cargar datos históricos (2006–2021)
# -----------------------------------------------------------------------------
load_historical <- function(path, year, encoding = "latin1") {
  read_csv(path, locale = locale(encoding = encoding)) |>
    rename_with(str_to_lower) |>
    select(
      table_id       = any_of(c("table_id", "mesa_de_votacion")),
      dept           = any_of(c("dept", "departamento")),
      prov           = any_of(c("prov", "provincia")),
      dist           = any_of(c("dist", "distrito")),
      eligible_voters = any_of(c("eligible_voters", "n_elec_habil")),
      total_voted    = any_of(c("total_voters", "n_cvas"))
    ) |>
    filter(prov %in% c("LIMA", "CALLAO")) |>
    mutate(
      year        = year,
      absenteeism = 1 - (total_voted / eligible_voters),
      delay_min   = 0L,   # sin retraso en años anteriores
      affected    = FALSE,
      dist        = normalizar_distrito(dist)
    )
}

lima_2006 <- load_historical(file.path(RAW, "lima_2006.csv"), 2006)
lima_2011 <- load_historical(file.path(RAW, "lima_2011.csv"), 2011)
lima_2016 <- load_historical(file.path(RAW, "lima_2016.csv"), 2016)
lima_2021 <- load_historical(file.path(RAW, "lima_2021.csv"), 2021)

cat("\n=== Tamaño de datasets históricos ===\n")
cat("2006:", nrow(lima_2006), "| 2011:", nrow(lima_2011),
    "| 2016:", nrow(lima_2016), "| 2021:", nrow(lima_2021), "\n")

# -----------------------------------------------------------------------------
# 3. Construir panel unificado
# -----------------------------------------------------------------------------
# Las mesas no son comparables entre años → usar distrito como unidad de merge
# Los datos históricos identifican baseline de ausentismo por distrito
# El efecto del retraso se identifica de la variación 2026 dentro del distrito

panel <- bind_rows(
  lima_2006 |> rename(district = dist) |> mutate(table_id = as.character(table_id)),
  lima_2011 |> rename(district = dist) |> mutate(table_id = as.character(table_id)),
  lima_2016 |> rename(district = dist) |> mutate(table_id = as.character(table_id)),
  lima_2021 |> rename(district = dist) |> mutate(table_id = as.character(table_id)),
  lima_2026 |> select(
    table_id, dept = department, prov = province,
    district = district_clean, year, eligible_voters,
    total_voted, absenteeism, delay_min, affected
  ) |> mutate(table_id = as.character(table_id))
) |>
  mutate(
    district = str_to_upper(str_trim(district)),
    year_fct = factor(year)
  ) |>
  # Excluir observaciones con absentismo imposible
  filter(
    absenteeism >= 0,
    absenteeism <= 1,
    eligible_voters > 0
  )

cat("\n=== Panel final ===\n")
cat("Filas totales:", nrow(panel), "\n")
cat("Distribución por año:\n")
print(count(panel, year))

# -----------------------------------------------------------------------------
# 4. Guardar
# -----------------------------------------------------------------------------
saveRDS(lima_2026,  file.path(CLEAN, "lima_2026_clean.rds"))
saveRDS(panel,      file.path(CLEAN, "panel.rds"))
write_csv(cobertura, file.path(CLEAN, "cobertura_distritos.csv"))

cat("\n✓ Datos guardados en data/clean/\n")
cat("NOTA: Re-ejecutar este script cuando se agreguen nuevas tablas al scraper.\n")
