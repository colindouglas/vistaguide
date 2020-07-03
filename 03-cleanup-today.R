suppressPackageStartupMessages({
  library(stringi)
  library(tidyverse)
  library(lubridate)
  source("cleanup-functions.R")
})

# Should we overwrite TSVs that already exist?
OVERWRITE <- FALSE

# Should we make OSM geocoding lookups for the properties that don't have data?
GEOCODE_MISSING <- TRUE

# Get a list of all of the CSV files
files <- list.files('data', pattern = "(listings)_[0-9]{9}\\.csv", full.names = TRUE)

for (file in files) {
  filename <- str_split(file, pattern = "\\.")[[1]][[1]]
  file_out <- paste0(filename, ".tsv")
  
  if (file.exists(file_out) & !OVERWRITE) {
    next()
  }
  
  x <- readLines(file)
  
  # Remove all of the dumb quotes the dumb real estate agents use for emphasis
  x <- gsub('"', "", x, fixed = TRUE)

  # Fix the delimiter between time and address
  x <- stri_replace_all(x, regex = "([0-9]{2}\\.[0-9]{6})(,)", replacement = "$1\t")
  
  # Fix the delimiter before URL
  x <- stri_replace_all(x, regex = "(,)(https)", replacement = "\t$2")
  
  # Fix ALL of the delimeters that are followed by a capital letter
  x <-stri_replace_all(x,  regex = "(,)([A-Z,])", replacement = "\t$2")
  
  # Only keep the rows where there's letters
  # Helps cleanup trailing garbage
  x <- paste(x[grepl("[A-Za-z]", x)], "\n")
  
  # Write the cleanup to a TSV file
  message(filename, " >> ", file_out)
  
  # Read the raw text as a tsv, clean up rows that aren't valid
  suppressWarnings(
    # This is a read_tsv call, even though file is a .csv
    tsv <- read_tsv(x, col_names = FALSE, col_types = cols(), guess_max = 10000) %>%
    mutate(X1 = as.POSIXct(X1, optional = TRUE)) %>%
    filter(!is.na(X1), !is.na(X2))
  )
  
  # Convert each row to chr
  rows <- map(1:nrow(tsv), ~ as.character(tsv[., ]))
  
  # Parse each row as a chr
  out <- map_dfr(rows, ~ parse_row(.))
  
  # Get lat/long of previous lookups to avoid unnecessary API calls to OSM
  geocode_lookup <- read_csv("data/geocode_lookup.csv", col_types = cols())
  out_geo <- left_join(out, geocode_lookup, by = "address")
  
  # Get a df of all of the rows where the geocode data is missing
  geo_missing <- filter(out_geo, is.na(osm_id))
  
  # If we want to lookup missing geocode information
  if (GEOCODE_MISSING & nrow(geo_missing) > 0) {
    
    # The rows where we were _successful_ in looking up prior geocode data
    geo_cached <- filter(out_geo, !is.na(osm_id))
    
    # Do geocode lookup on the addresses where we don't have geocode data
    geo_missing_lookups <- geo_missing %>%
      select(address) %>%
      rowwise() %>%
      mutate(geocode = list(get_latlong(address, quiet = FALSE)))  %>%
      unnest_wider(geocode) %>%
      map_dfc(unlist) %>%
      mutate_at(vars(-osm_type, -address, -osm_displayname), as.numeric)
    
    # Update the geocode lookup cache
    
    # Find the rows where we didn't have cached data but 
    # we were successful in looking it up from the API
    geo_newlookups <- geo_missing %>%
      filter(!is.na(osm_id)) %>%
      select(names(geocode_lookup))

    # Add the new successful lookups to the old cache, then keep only the distinct rows
    geocode_lookup <- bind_rows(geocode_lookup, geo_newlookups) %>%
      distinct(osm_id, .keep_all = TRUE) # Porbably not necessary
    
    # Perform the lookup with the new geocode cache
    out_geo <- left_join(out, geocode_lookup, by = "address")
    
    # Write the cached lookups for future use
    write_csv(geocode_lookup, path = "data/geocode_lookup.csv")

  } 
  
  # Write to .tsv
  write_tsv(out_geo, path = file_out)
}
