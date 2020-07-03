suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})
source("setup.R")

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
                            ))) %>%
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
)


# Postal Code Cleanup -----------------------------------------------------
# Read in list of postal codes
fsa_ns <- read_csv("data/ca-postal-codes.csv", col_types = cols()) %>%
  filter(Province_abbr == "NS") %>%
  select(postal_first = Postal_Code, postal_city = `Place_Name`)

# Location binning -------------------------------------------------------

listings_u <- listings_all %>%
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