library(tidyverse)
library(readxl)

#load data
install <- read_csv("/Users/mathieurojas/Documents/datapol/peru/election_day/lima_install_2026.csv")
votes <- read_csv("/Users/mathieurojas/Documents/datapol/peru/election_day/lima_votes_2026.csv")
peru_2021 <- read_delim("/Users/mathieurojas/Documents/datapol/peru/election_day/peru_2021.csv", delim = ";")
peru_2016 <- read_delim("/Users/mathieurojas/Documents/datapol/peru/election_day/peru_2016.csv", delim = ";")
peru_2011 <- read_excel("/Users/mathieurojas/Documents/datapol/peru/election_day/peru_2011.xlsx")
peru_2006 <- read_delim("/Users/mathieurojas/Documents/datapol/peru/election_day/peru_2006.csv", delim = ";")


lima_2026 <- install |>
  full_join(votes, by = "table_id") |>
  janitor::clean_names() |>
  select(table_id, dept = department, prov = province, dist = district, installation_time, eligible_voters, total_voters = total_voted, rp = renovacion_popular, jpp = juntos_por_el_peru) |>
  filter(!is.na(district) & !is.na(eligible_voters))

disitrcts <- lima_2026 |>
  select(department, province, district) |>
  distinct()

lima_2021 <- peru_2021 |>
  select(table_id = MESA_DE_VOTACION, dept = DEPARTAMENTO, prov =PROVINCIA, dist = DISTRITO,  eligible_voters = N_ELEC_HABIL, total_voters = N_CVAS) |>
  filter(prov == "LIMA" | prov == "CALLAO")

lima_2016 <- peru_2016 |>
  select(table_id = MESA_DE_VOTACION, dept = DEPARTAMENTO, prov =PROVINCIA, dist = DISTRITO,  eligible_voters = N_ELEC_HABIL, total_voters = N_CVAS) |>
  filter(prov == "LIMA" | prov == "CALLAO")

lima_2011 <- peru_2011 |>
  select(table_id = MESA_DE_VOTACION, dept = DEPARTAMENTO, prov =PROVINCIA, dist = DISTRITO,  eligible_voters = N_ELEC_HABIL, total_voters = N_CVAS) |>
  filter(prov == "LIMA" | prov == "CALLAO")

lima_2006 <- peru_2006  |>
  select(table_id = MESA_DE_VOTACION, dept = DEPARTAMENTO, prov =PROVINCIA, dist = DISTRITO,  eligible_voters = N_ELEC_HABIL, total_voters = N_CVAS) |>
  filter(prov == "LIMA" | prov == "CALLAO")


write_csv()