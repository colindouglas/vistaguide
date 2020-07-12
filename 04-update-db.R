suppressPackageStartupMessages(
  library(tidyverse)
)

geocode_missing <- TRUE

# Insert new rows into 'properties' table ---------------------------------
# Select the right columns from the output df
properties_add <- out %>%
  arrange(desc(datetime)) %>%
  select(-update_id, -status, -price, -days_on_market, last_update = datetime) %>%
  group_by(prop_id) %>%
  summarize_at(vars(-group_cols()), ~ best_value(.)) 

# Double check for duplicates
properties_exist <- tbl(dbcon, "properties") %>%
  select(prop_id) %>%
  distinct() %>%
  collect()
properties_add <- anti_join(properties_add, properties_exist, by = "prop_id")

# Write to DB
message(file, ": ", nrow(properties_add), " new rows in 'property'")
dbWriteTable(dbcon, "properties", properties_add, append = TRUE)

# Insert new rows into 'updates' table ------------------------------------
# Select the right columns from the output df
updates_add <- out %>%
  select(update_id, datetime, prop_id, status, price, days_on_market, source_file) %>%
  distinct() %>%
  filter(!is.na(update_id)) # Catch exceptions where the key is NA

# Double check for duplicates
updates_exist <- tbl(dbcon, "updates") %>%
  select(update_id) %>%
  distinct() %>%
  collect()

updates_add <- anti_join(updates_add, updates_exist, by = "update_id")

# WRite to DB
message(file, ": ", nrow(updates_add), " new rows in 'updates'")
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
    message(file, ": ", nrow(geocode_missing), " API requests for geocoding data")
    # Do OSM lookups on the places with missing geocodes
    geocode_add <- geocode_missing %>%
      distinct(address, .keep_all = FALSE) %>%
      rowwise() %>%
      mutate(geocode = list(get_latlong(address, quiet = TRUE)))  %>%
      unnest_wider(geocode) %>%
      map_dfc(unlist) %>%
      mutate_at(vars(-osm_type, -address, -osm_displayname), as.numeric)
    
    # Write the new lookups to the table
    
    message(file, ": ", nrow(geocode_add), " new rows in 'geocode'")
    dbWriteTable(dbcon, "geocode", geocode_add, append = TRUE)
    
    
    # Validation - Won't stop anything but will at least throw an error into the logs
    # Columns are the same in the new geocode data and the 
    stopifnot(
      setequal(
        names(geocode_add),
        c("address", "lat", "lon", "osm_id", "osm_type", "osm_importance", 
          "osm_displayname", "place_id")
      ))
  }}
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
    c("update_id", "prop_id", "datetime", "status", "price", "days_on_market", "source_file")
  ))