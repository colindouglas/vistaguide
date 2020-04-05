library(tidyverse)
library(lubridate)

# For x = 'prefix: data' return 'data'
drop_prefix <- function(x, prefix) {
  out <- str_replace(x, prefix, '') %>% str_trim() %>% pluck(1)
  if (out == '' | out == "N/A") out <- NA
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

# Open all of the files that match listing_ddddddddd.csv in the folder, bind them together
files <- list.files('data/', pattern = "(listings)_[0-9]{9}\\.csv", full.names = TRUE)
raw_rows <- suppressWarnings(map_dfr(files, ~ read_tsv(., col_names = FALSE)))


# Function to parse the not-necessarily-ordered fields in a row
parse_row <- function(row) {
  row <- as.character(row) # Convert everything to chr so we don't get NAs
  out <- list()
  
  out$datetime <- as_datetime(as.numeric(row[1]))
  
  # Split the "address" field into the street address and the postal code
  out$address <- row[2]
  out$postal <- str_extract(out$address, '[A-Za-z]\\d[A-Za-z][ -]?\\d[A-Za-z]\\d')
  out$address <- str_replace(out$address, paste(',', out$postal), '')
  
  # Deal with the URL and the description, which are always in the same position
  out$url <- row[3]
  out$description <- row[4]
  
  # Everything from here down is not always in the same position in the row
  # Therefore we need to test to see which field it is before parsing
  
  # This is a list of fields that are expected to return factors/character strings
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
    "Utilities" = "utilities",
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

# Turn each row into a a character vector, store in a list called rows
rows <- map(1:nrow(raw_rows), ~ as.character(raw_rows[., ]))

# Map over each list and apply to parse_row() function
listings <- map_dfr(rows, ~ parse_row(.))


listings_u <- listings %>%
  # Keep only the unique rows, because sometimes things get posted more than once
  distinct(address, url, date = as_date(datetime), price, status, .keep_all = TRUE) %>%
  select(-date) %>%
  # Split the postal code up for easier analysis
  separate(postal, 
           into = c("postal_first", "postal_last"), 
           sep = " ", remove = FALSE) %>%
  # Put the unit numbers for apartments/condos into their own column, take it out of the address
  mutate(
    unit = case_when(
      grepl("Unit \\d+", address) ~ str_replace(str_extract(address, pattern = "Unit \\d+"), "Unit ", ""),
      TRUE ~ as.character(NA)),
    address = str_replace(address, pattern = "Unit \\d+ ", "")
    ) %>%
  # Split the address into a street and a city
  separate(address, into = c("street", "city"), sep = ", ", remove = FALSE)
    
    

# Where to write the output file
todays_date <- format(Sys.Date(), format = "%Y%m%d")
path_out <- paste0("data/listings-clean_", todays_date, ".csv")

# Write the file
write_csv(listings_u, path = path_out, na = "")

          