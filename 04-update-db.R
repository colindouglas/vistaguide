geocode_missing <- TRUE

# Insert new rows into 'properties' table ---------------------------------
properties_add <- out %>%
  arrange(desc(datetime)) %>%
  select(-update_id, -status, -price, -days_on_market, last_update = datetime) %>%
  group_by(prop_id) %>%
  summarize_at(vars(-group_cols()), ~ best_value(.))

dbWriteTable(dbcon, "properties", properties_add, append = TRUE)

# Insert new rows into 'updates' table ------------------------------------
updates_add <- out %>%
  select(update_id, datetime, prop_id, status, price, days_on_market) %>%
  distinct()

dbWriteTable(dbcon, "updates", updates_add, append = TRUE)


# Insert new rows into 'geocode' table ------------------------------------
if (geocode_missing) {
  # Get lat/long of previous lookups to avoid unnecessary API calls to OSM
  geocode_lookup <- tbl(dbcon, "geocode") %>%
    select(address) %>%
    collect()
  
  # Get a df of all of the rows where the geocode data is missing
  geocode_missing <- anti_join(out, geocode_lookup, by = "address")
  
  if (nrow(geocode_missing) > 0) {
  # Do OSM lookups on the places with missing geocodes
  geocode_add <- geocode_missing %>%
    distinct(address, .keep_all = FALSE) %>%
    rowwise() %>%
    mutate(geocode = list(get_latlong(address, quiet = TRUE)))  %>%
    unnest_wider(geocode) %>%
    map_dfc(unlist) %>%
    mutate_at(vars(-osm_type, -address, -osm_displayname), as.numeric)
  
  # Write the new lookups to the table
  dbWriteTable(dbcon, "geocode", geocode_add, append = TRUE)
  }
  
  # Validation - Won't stop anything but will at least throw an error into the logs
  # Columns are the same in the new geocode data and the 
  stopifnot(
    setequal(
      names(geocode_add),
      c("address", "lat", "lon", "osm_id", "osm_type", "osm_importance", 
        "osm_displayname", "place_id")
    ))
}
# Properties have all of the important attributes
stopifnot(
  all(
    c("prop_id", "last_update", "address", "street", "city", "postal", 
      "url", "description", "mls_no", "pid", "list_date",
      "postal_city", "loc_bin") %in% 
      names(properties_add) 
  ))


# Updates have all of the important attributes
stopifnot(
  setequal(
    names(updates_add),
    c("update_id", "prop_id", "datetime", "status", "price", "days_on_market")
  ))