# This script is used to make the file that is used as the initial geocode lookup
# Each time the data is updated, new geocode data is added to the end of the file
# It likely never needs to be run again. - Colin, 2-July-2020

files <- list.files(path = "data", pattern = "listings_[0-9]{9}.tsv", full.names = TRUE)

listings_all <- suppressWarnings(
  map_dfr(files, ~ read_tsv(., guess_max = 10000,
                            col_types = cols()))
)

geocode_lookup <- listings_all %>% 
  distinct(address, lat, lon, osm_id, place_id, osm_type, osm_importance, osm_displayname) %>%
  filter(!is.na(osm_id))

write_csv(geocode_lookup, path = "data/geocode_lookup.csv")
