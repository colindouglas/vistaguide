suppressPackageStartupMessages({
  library(stringi)
  library(tidyverse)
  library(lubridate)
  source("cleanup-functions.R")
  source("connect-db.R")
  source("setup-constants.R")
})

# Should we overwrite TSVs that already exist?
OVERWRITE <- FALSE

# Should we make OSM geocoding lookups for the properties that don't have data?
GEOCODE_MISSING <- TRUE

# Get a list of all of the CSV files
files <- list.files('data', pattern = "(listings)_[0-9]{9}\\.csv", full.names = TRUE)

for (file in files) {
  # Print status message
  message(file, ": cleaning...")
  filename <- str_split(file, pattern = "\\.")[[1]][[1]]
  file_out <- paste0(filename, ".done")
  
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
  
  # Fix ALL of the delimiters that are followed by a capital letter
  x <- stri_replace_all(x,  regex = "(,)([A-Z,])", replacement = "\t$2")
  
  # Only keep the rows where there's letters, helps filter out garbage
  x <- paste(x[grepl("[A-Za-z]", x)], "\n")
  
  # Read the raw text as a tsv, clean up rows that aren't valid
  suppressWarnings(
    # This is a read_tsv call, even though file is a .csv
    tsv <- read_tsv(x, col_names = FALSE, col_types = cols(), guess_max = 10000) %>%
      mutate(X1 = as.POSIXct(X1, optional = TRUE)) %>%
      filter(!is.na(X1), !is.na(X2))
  )
  
  # Convert each row to chr
  rows <- map(1:nrow(tsv), ~ as.character(tsv[., ]))
  
  integer_cols <- c("update_id", "prop_id", "price", "days_on_market", 
                    "mls_no", "pid", "assessment", "assessment_year",
                    "bedrooms", "bathrooms", "sqft_mla", "sqft_tla",
                    "building_age")
  # Parse each row as a chr
  out <- map_dfr(rows, ~ parse_row(.)) %>%
    mutate_at(vars(any_of(integer_cols)), ~ as.numeric(.))
  
  # Add prop_ids to new properties ------------------------------------------
  
  # Get the identifiers of the properties that are already in the DB
  properties_lookup <- tbl(dbcon, "properties") %>%
    select(prop_id, mls_no, address) %>%
    distinct() %>%
    collect()
  
  # Find the last property ID used in the database
  last_prop_id <- max(as.numeric(properties_lookup$prop_id), na.rm = TRUE)
  
  # Find the properties that aren't in the DB yet
  # Assign the new properties new property ID keys
  properties_new <- anti_join(out, properties_lookup, by = c("address", "mls_no")) %>%
    group_by(address, mls_no) %>%
    mutate(prop_id = cur_group_id() + last_prop_id) %>%
    distinct(prop_id, .keep_all = TRUE)

  # Reassemble the known and new properties with IDs
  properties_existing <- anti_join(out, properties_new, by = c("address", "mls_no")) %>%
    left_join(properties_lookup, by = c("address", "mls_no"))
  
  out <- bind_rows(properties_existing, properties_new)
  
  # Small misc. data cleanups -----------------------------------------------
  out <- out %>%
    filter(!is.na(address), !is.na(datetime)) %>%
    # Split the postal code into a "field" field and a "last" field
    separate(postal, into = c("postal_first", "postal_last"), sep = " |\\-", remove = FALSE) %>%
    mutate(
      # Put the unit numbers for apartments/condos into their own column, take it out of the address
      unit = ifelse(
        grepl("Unit \\d+", address),
        str_replace(str_extract(address, pattern = "Unit \\d+"), "Unit ", ""),
        as.character(NA)
      ),
      address = str_remove_all(address, pattern = "Unit \\d+ "),
      
      # Catches bug where the last two digits of the price don't come through
      price = ifelse(price < 10000, price*100, price),
      
      # Fix the URL so following it doesn't bring up a print preview automatically
      url = str_remove_all(url, pattern = "&print=1"),
      
      # Calculate a unique ID for each row
      update_id = as.numeric(paste0(as.numeric(as.POSIXct(datetime)), substring(mls_no, 5, 9))),
      source_file = file,
    ) %>%
    
    # Split the address into a street and a city
    separate(address, into = c("street", "city"), sep = ", ", remove = FALSE, extra = "merge") 

  # Bin the locations -------------------------------------------------------
  
  ns_postals <- tbl(dbcon, "postals") %>%
    filter(province == "NS") %>%
    select(postal = postal_code, postal_city = place_name) %>%
    collect()
  
  out <- left_join(out, ns_postals, by = "postal") %>%
    mutate(peninsula = peninsula_codes[postal_first],
           loc_bin = factor(
             case_when(
               postal_first %in% names(peninsula_codes) ~ "Halifax Peninsula",
               grepl("Halifax", postal_city)  ~ "Halifax, Off Peninsula",
               grepl("Dartmouth", postal_city) ~ "Dartmouth",
               postal_first %in% hrm_postals ~ "HRM, Other",
               TRUE ~ "Rest of Province"), 
             levels = c("Halifax Peninsula", "Halifax, Off Peninsula", "Dartmouth", "HRM, Other", "Rest of Province")))  
  
  # Update the database
  message(file, ": inserting...")
  source("04-update-db.R")
  
  # Rename the file once it's been processed
  file.rename(file, paste0(filename, ".done"))
  message(file, " >> ", filename, ".done")
}

