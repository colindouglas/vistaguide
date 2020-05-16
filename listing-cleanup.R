library(tidyverse)
library(lubridate)

# Convert the weird CSVs that aren't formated right to TSVs
source("csv_to_tsv.R")
source("setup.R")

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

# Open all of the files that match listing_ddddddddd.csv in the folder, bind them together
files <- list.files('data', pattern = "(listings)_[0-9]{9}\\.tsv", full.names = TRUE)
raw_rows <- map_dfr(files, function(x) {
  message("Reading ", x)
  suppressWarnings(out <- read_tsv(x, col_names = FALSE, col_types = cols(), guess_max = 10000))
  filter(out, !is.na(X2))
})


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

# Turn each row into a a character vector, store in a list called rows
rows <- map(1:nrow(raw_rows), ~ as.character(raw_rows[., ]))

# Map over each list and apply to parse_row() function
listings <- map_dfr(rows, ~ parse_row(.))


listings_u <- listings %>%
  # Split the postal code up for easier analysis
  separate(postal,
           into = c("postal_first", "postal_last"),
           sep = " |\\-", remove = FALSE) %>%
  # Put the unit numbers for apartments/condos into their own column, take it out of the address
  mutate(
    unit = case_when(
      grepl("Unit \\d+", address) ~ str_replace(str_extract(address, pattern = "Unit \\d+"), "Unit ", ""),
      TRUE ~ as.character(NA)),
    address = str_replace(address, pattern = "Unit \\d+ ", ""),
    price = case_when(
      price < 10000 ~ price*100, # Catches bug where the last two digits of the price don't come through
      TRUE ~ price),
    url = str_replace(url, pattern = "&print=1", replacement = "")
    ) %>%
  # Split the address into a street and a city
  separate(address, into = c("street", "city"), sep = ", ", remove = FALSE)


# Postal Code Cleanup -----------------------------------------------------

# # Read in list of postal codes
# fsa_ns <- read_csv("data/canada_fsa.csv", col_types = cols())  %>%
#   filter(`FSA-Province` == 12) %>% # NS
#   select(postal = PostalCode, postal_city = `Place Name`, area_type = AreaType) %>%
#   mutate(postal = paste(substring(postal, 1, 3), substring(postal, 4, 6)))

# Read in list of postal codes
fsa_ns <- read_csv("data/ca-postal-codes.csv", col_types = cols()) %>%
  filter(Province_abbr == "NS") %>%
  select(postal_first = Postal_Code, postal_city = `Place_Name`, long = Longitude, lat = Latitude)

# Location binning -------------------------------------------------------

listings_u <- listings_u %>%
  left_join(fsa_ns, by = "postal_first") %>%
  mutate(peninsula = peninsula_codes[postal_first],
         loc_bin = factor(
           case_when(
             postal_first %in% names(peninsula_codes) ~ "Halifax Peninsula",
             grepl("Halifax", postal_city)  ~ "Halifax, Off Peninsula",
             grepl("Dartmouth", postal_city) ~ "Dartmouth",
             postal_first %in% hrm_postals ~ "HRM, Other",
             TRUE ~ "Rest of Province"), 
           levels = c("Halifax Peninsula", "Halifax, Off Peninsula", "Dartmouth", "HRM, Other", "Rest of Province")))

# Sometimes the listings are "Sold" but they haven't closed yet, count those as "Pending"
listings_u$status[is.na(listings_u$price)] <- "Pending"


# Where to write the output file
path_out <- paste0("data/listings-clean.csv")

# Write the file
write_csv(listings_u, path = path_out, na = "")