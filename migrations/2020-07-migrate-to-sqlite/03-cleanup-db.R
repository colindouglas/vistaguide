suppressPackageStartupMessages({
  library(tidyverse)
  source("connect-db.R")
})

# Remove duplicate entries in some tables
# Duplicates in 'properties' ----------------------------------------------
properties <- collect(tbl(dbcon, "properties"))
properties_clean <- distinct(properties, prop_id, .keep_all = TRUE)

if (nrow(properties) != nrow(properties_clean)) {
  message("properties: ", nrow(properties),  " >> ", nrow(properties_clean))
  dbWriteTable(dbcon, 
               "properties", 
               properties_clean, 
               overwrite = TRUE)
} else {
  message("properties: no changes")
}

# Duplicates in 'geocode' -------------------------------------------------
geocode <- collect(tbl(dbcon, "geocode"))
geocode_clean <- distinct(geocode, address, .keep_all = TRUE)

if (nrow(geocode) != nrow(geocode_clean)) {
  message("geocode: ", nrow(geocode),  " >> ", nrow(geocode_clean))
  dbWriteTable(dbcon, 
               "geocode", 
               geocode_clean, 
               overwrite = TRUE)
} else {
  message("geocode: no changes")
}

# Duplicates in 'updates' -------------------------------------------------
updates <- collect(tbl(dbcon, "updates"))
updates_clean <- distinct(updates, update_id, .keep_all = TRUE)


if (nrow(updates) != nrow(updates_clean)) {
  message("updates: ", nrow(updates),  " >> ", nrow(updates_clean))
  dbWriteTable(dbcon, 
               "updates", 
               updates_clean, 
               overwrite = TRUE)
} else {
  message("updates: no changes")
}
