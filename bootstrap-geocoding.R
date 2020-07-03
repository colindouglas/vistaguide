files <- list.files(path = "data", pattern = "listings_[0-9]{9}.tsv", full.names = TRUE)

listings_all <- suppressWarnings(
  map_dfr(files, ~ read_tsv(., guess_max = 10000,
                            col_types = cols(
                              .default = col_character(),
                              datetime = col_datetime(),
                              price = col_double(),
                              list_date = col_date(),
                              days_on_market = col_integer(), 
                              assessment = col_double(),
                              assessment_year = col_integer(),
                              bedrooms = col_integer(),
                              bathrooms = col_integer(),
                              sqft_mla = col_double(),
                              sqft_tla = col_double(),
                              condo_fee = col_double(),
                              garage = col_logical(),
                              lat = col_double(),
                              long = col_double(),
                              osm_id = col_integer(),
                              place_id = col_integer(),
                              osm_importance = col_double()
                            )))
)

geocode_lookup <- listings_all %>% 
  distinct(address, lat, lon, osm_id, place_id, osm_type, osm_importance, osm_displayname) %>%
  filter(!is.na(osm_id))

write_csv(geocode_lookup, path = "data/geocode_lookup.csv")
