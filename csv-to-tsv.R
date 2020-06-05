library(stringi)
library(tidyverse)
source("cleanup-functions.R")

# Should we overwrite TSVs that already exist?
OVERWRITE <- FALSE

# Get a list of all of the CSV files
files <- list.files('data', pattern = "(listings)_[0-9]{9}\\.csv", full.names = TRUE)

for (file in files) {
  filename <- str_split(file, pattern = "\\.")[[1]][[1]]
  file_out <- paste0(filename, ".tsv")
  
  if (file.exists(file_out) & !OVERWRITE) {
    next()
  }
  
  x <- readLines(file) 

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
  
  # Get lat/long from OSM
  out_geo <- out %>%
    rowwise() %>%
    mutate(geocode = list(get_latlong(address, quiet = FALSE)))  %>%
    unnest_wider(geocode) %>%
    map_dfc(unlist)
  
  
  # Write to .tsv
  write_tsv(out_geo, path = file_out)
}
