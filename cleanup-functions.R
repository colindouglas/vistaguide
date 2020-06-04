# For x = 'prefix: data' return 'data'
drop_prefix <- function(x, prefix) {
  out <- str_replace(x, prefix, '') %>% str_trim() %>% pluck(1)
  if (out == 'Yes') out <- TRUE
  if (out == 'No') out <- FALSE
  if (out == '' | out == "N/A" | out == "None") out <- NA
  return(out)
}

# For x with a price listed as $1,000,000.00, return 1000000
extract_money <- function(x) {
  x %>%
    str_extract('\\$\\d*,?\\d*,*\\d+') %>%
    str_replace_all(",|\\$", '') %>%
    as.numeric()
}

# For x with a value listed as 1,000,000.00, return 1000000
extract_number <- function(x) {
  x %>%
    str_extract('\\d*,?\\d*,*\\d+\\.*\\d*') %>%
    str_replace_all(",", '') %>%
    as.numeric()
}


# Function to parse the not-necessarily-ordered fields in a row
parse_row <- function(row) {
  row <- as.character(row) # Convert everything to chr so we don't get NAs
  out <- list()
  
  out$datetime <- as_datetime(as.numeric(row[1]))
  
  # Split the "address" field into the street address and the postal code
  out$address <- row[2]
  out$postal <- str_extract(out$address, '[A-Za-z]\\d[A-Za-z][ -]?\\d[A-Za-z]\\d')
  out$address <- str_replace(out$address, paste(',', out$postal), '')
  
  # If there's no space in the postal code, add one
  out$postal[
    (nchar(out$postal) == 6 & !grepl(" ", out$postal)) # Without a space in between
    ] <- paste(substring(out$postal, 1, 3), substring(out$postal, 4, 6))
  
  
  # Deal with the URL and the description, which are always in the same position
  out$url <- row[3]
  out$description <- row[4]
  
  # Everything from here down is not always in the same position in the row
  # Therefore we need to test to see which field it is before parsing
  
  # This is a list of fields that are expected to return factors/character strings
  # This needs to match the prefix exactly (missing whitespace is OK) because it is regex'd out
  field_shortcodes_fct <- c(
    "Sewer:" = "sewer",
    "Water:" = "water",
    "Lising Size:" = "listing_size",
    "Heating:" = "heating",
    "Land Features:" = "land_features",
    "Water:" = "water",
    "Sewer:" = "sewar",
    "Status:" = "status",
    "MLS® #" =  "mls_no",
    "PID" = "pid",
    "Lot Size" = "lot_size",
    "Listed By" = "agent",
    "Garage Type:" = "garage_type",
    "Fuel Type:" = "fuel_type",
    "Type" = "type",
    "Building Style" = "building_style",
    "Style" = "style",
    "Land Features:" = "land_features",
    "Foundation:" = "foundation",
    "Basement:" = "basement",
    "Driveway/Pkg:" = "driveway",
    "Utilities:" = "utilities",
    "Features:" = "features",
    "Roof:" = "roof",
    "Flooring:" = "flooring",
    "Garage:" = "garage",
    "Waterfront:" = "waterfront",
    "Rental Equipment:" = "rental_equipment",
    "Exterior:" = "exterior",
    "Elementary School:" = "school_elem",
    "Jr High School:" = "school_jrhigh",
    "High School:" = "school_high",
    "Compliments of:" = "compliments_of")
  
  # This is a list of fields that are expected to return numerics
  # They don't need to match the prefix exactly beccause the number is extracted from them
  field_shortcodes_num <- c(
    "Sq. Footage" = "sqft_mla",
    "Total Fin Sq. Footage" = "sqft_tla",
    "Prov. Parcel Size" = "parcel_size",
    "Bedrooms:" = "bedrooms",
    "Bathrooms:" = "bathrooms",
    "Building Age:" = "building_age"
  )
  
  field_regex_num <- paste(names(field_shortcodes_num), collapse = "|")
  field_regex_fct <- paste(names(field_shortcodes_fct), collapse = "|")
  
  # Loop through each column in the row and apply the appropriate formating
  for (field in tail(row, -4)) {
    
    # Handle the 'Price' field by extracting the number, removing commas
    if (grepl("Price", field)) {
      out$price <- extract_money(field)
    }
    
    # Parse out the assessment. This requires special treatment because
    # we need to get the year and the dollar value out of it
    if (grepl("Assessment", field)) {
      out$assessment <- extract_money(field)
      out$assessment_year <- field %>%
        str_extract('\\(\\d{4}\\)') %>%
        str_replace_all('\\(|\\)', '') %>%
        as.numeric()
    }
    
    if (grepl("Condo Fee", field)) {
      out$condo_fee <- extract_money(field)
    }
    
    # Parse out the listing date. This needs special treatment
    # because we have to turn it into a date and calculate days on the market
    if (grepl("List Date", field)) {
      out$list_date <- ymd(str_extract(field, "20\\d{2}-\\d{2}-\\d{2}"))
      out$days_on_market <- as_date(out$datetime) - out$list_date
    }
    
    # Handle fields that are factors
    if (grepl(field_regex_fct, field)) {
      field_name <- str_extract(field, field_regex_fct)
      field_short <- field_shortcodes_fct[field_name]
      out[[field_short]] = drop_prefix(field, prefix = field_name)
    }
    
    # Handle fields that are numeric
    if (grepl(field_regex_num, field)) {
      field_name <- str_extract(field, field_regex_num)
      field_short <- field_shortcodes_num[field_name]
      out[[field_short]] = extract_number(field)
    }
  }
  return(out)
}

get_latlong <- function(address, quiet = TRUE) {
  
  # If the address starts with a unit number, strip it
  address <- str_replace(address, pattern = "^Unit [0-9]+ ", "")
  
  # If the address starts with "Lot", strip it
  address <- str_replace(address, pattern = "^Lot ", "")
  
  # If the address ends wqith that stupid  "For sale" bullshit, get rid of it
  address <- str_replace(address, pattern = ", Nova Scotia - For Sale \\$[0-9]+,[0-9]+", "")
  
  # Add "NS, Canada" to the end of every address if it's not already there
  if (!grepl("NS, Canada", address)) {
    address <- paste0(address, ", NS, Canada")
  }
  
  Sys.sleep(1)
  
  tryCatch(
    expr = {
      geocode <- list(tmaptools::geocode_OSM(
        paste0(address),
        details = TRUE,
        geometry = "point", 
        return.first.only = TRUE))[[1]]
      
      out <- list(
        "lat" = geocode$coords[["x"]],
        "long" = geocode$coords[["y"]],
        "osm_id" = geocode[["osm_id"]],
        "place_id" = geocode[["place_id"]],
        "osm_type" = geocode[["type"]],
        "osm_importance" = geocode[["importance"]],
        "osm_displayname" = geocode[["display_name"]])
        
        if (!quiet) {
          message("Geocode successful: ", address)
        }
      },
    warning = function(w) {
      message("Warning @", address, " ", w)
      
      out <- list(
        "lat" = NA_real_,
        "long" = NA_real_,
        "osm_id" = NA_integer_,
        "place_id" = NA_integer_,
        "osm_type" = NA_character_,
        "osm_importance" = NA_real_,
        "osm_displayname" = NA_character_
      )
      
    },
    error = function(e) {
      
      if (!quiet) {
        message("Geocode failed: ", address)
      }
      
      out <- list(
        "lat" = NA_real_,
        "long" = NA_real_,
        "osm_id" = NA_integer_,
        "place_id" = NA_integer_,
        "osm_type" = NA_character_,
        "osm_importance" = NA_real_,
        "osm_displayname" = NA_character_
      )})
  return(out)
}
