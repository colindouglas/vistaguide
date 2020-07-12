# This script is for converting from the (bad) csv/tsv method used prior to July 3rd to an SQLite based method
library(tidyverse)
library(snakecase)
source("connect-db.R")
source("cleanup-functions.R")

OVERWRITE <- TRUE
listings_clean <- read_csv("data/listings-clean.csv") %>%
  group_by(address, mls_no) %>%
  mutate(prop_id = cur_group_id(),
         source_file = NA_character_) %>%
  ungroup()

stopifnot(nrow(listings_clean) > 30000) # Just in case I do something dumb

# TABLE: postals ----------------------------------------------------------
# KEY: postal_code
# DESC: contains information on Canadian postal codes

canada_fsa <- read_csv("data/canada_fsa.csv")
names(canada_fsa) <- to_snake_case(names(canada_fsa))

fsa_to_prov <- c(
  "10" = "NL",
  "12" = "NS",
  "11" = "PE",
  "13" = "NB",
  "24" = "PQ",
  "35" = "ON",
  "46" = "MB",
  "47" = "SK",
  "48" = "AB",
  "59" = "BC",
  "61" = "NU",
  "62" = "NW",
  "60" = "YK")

canada_fsa <- canada_fsa %>%
  mutate(province = fsa_to_prov[as.character(fsa_province)],
         postal_code = paste(substring(postal_code, 1, 3), substring(postal_code, 4, 6))) %>%
  rename(lon = longitude, lat = latitude) %>%
  filter(province == "NS")

dbWriteTable(dbcon, "postals", canada_fsa, overwrite = OVERWRITE)


# TABLE: properties -------------------------------------------------------
# Describes attributes of the properties that aren't likely to change over time
# KEY: mls_id
# LINKAGES: 
  # properties:address > geocode:address
  # updates:mls_id > properties>

# THINGS THAT AREN'T HERE: datetime, price, days_on_market, status, lat/lon, everything that starts with osm

# Drop the columns that might vary within the same listing
properties <- listings_clean %>%
  select(-price, -days_on_market, -status,  # Properties of the 'scrape', separate table
         -lat, -lon, -starts_with("osm"), -place_id) # Properties of 'geocode', separate table

# For columns that _should_ be the same, but aren't, delegate the collapse to the best_value()
# function that lives in cleanup-functions.R
properties <- properties %>%
  filter(!is.na(address)) %>%
  group_by(prop_id) %>%
  mutate_at(vars(-group_cols()), ~ best_value(.)) %>%
  arrange(desc(datetime)) %>%
  distinct(prop_id, .keep_all = TRUE) %>%
  select(prop_id, last_update = datetime, address, loc_bin, postal, everything())

dbWriteTable(dbcon, "properties", properties, overwrite = TRUE,
             field.types = c(last_update = "text",
                             prop_id = "integer", 
                             last_update = "character", 
                             address = "character", 
                             loc_bin = "character", 
                             postal = "character", 
                             street = "character", 
                             city = "character", 
                             postal_first = "character", 
                             postal_last = "character", 
                             url = "character", 
                             description = "character", 
                             mls_no = "integer", 
                             pid = "integer", 
                             list_date = "character", 
                             assessment = "integer", 
                             assessment_year = "integer", 
                             bedrooms = "integer",
                             bathrooms = "integer", 
                             sqft_mla = "integer", 
                             sqft_tla = "integer", 
                             lot_size = "character", 
                             agent = "character", 
                             type = "character", 
                             building_style = "character", 
                             parcel_size = "character", 
                             building_age = "integer", 
                             heating = "character", 
                             land_features = "character", 
                             water = "character", 
                             sewer = "character", 
                             foundation = "character", 
                             basement = "character", 
                             driveway = "character", 
                             fuel_type = "character", 
                             utilities = "character", 
                             features = "character", 
                             roof = "character", 
                             flooring = "character", 
                             garage = "character", 
                             garage_type = "character", 
                             waterfront = "character", 
                             rental_equipment = "character", 
                             exterior = "character", 
                             compliments_of = "character", 
                             style = "character", 
                             school_elem = "character", 
                             school_jrhigh = "character", 
                             school_high = "character", 
                             condo_fee = "integer", 
                             unit = "character", 
                             postal_city = "character",
                             peninsula = "character", 
                             source_file = "character"))

# TABLE: geocode -------------------------------------------------------
# Describes geocoded data pulled from OSM
# KEY: address

geocode <- listings_clean %>%
  select(address, lat, lon, starts_with("osm"), place_id) %>% 
  distinct(address, .keep_all = TRUE)

dbWriteTable(dbcon, "geocode", geocode, overwrite = TRUE)

# TABLE: Updates ----------------------------------------------------------

# Describes geocoded data pulled from 
# KEY: update_id


updates <- listings_clean %>%
  mutate(update_id = paste0(as.numeric(as.POSIXct(datetime)), substring(mls_no, 5, 9))) %>%
  select(update_id, prop_id, datetime, status, price, days_on_market, source_file) %>%
  distinct(update_id, .keep_all = TRUE)

dbWriteTable(dbcon, "updates", updates, overwrite = TRUE,
             field.types = c(datetime = "text",
                             update_id = "integer", 
                             prop_id = "integer", 
                             status = "character", 
                             price = "integer", 
                             days_on_market = "integer"))
