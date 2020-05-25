library(stringi)
library(tidyverse)

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
  x <- x[grepl("[A-Za-z]", x)]
  
  # Write the cleanup to a TSV file
  message(filename, " >> ", file_out)
  # writeLines(x, con = file_out)
  
  suppressWarnings(
    tsv <- read_tsv(x, col_names = FALSE, col_types = cols(), guess_max = 10000) %>%
      mutate(X1 = as.POSIXct(X1, optional = TRUE)) %>%
      filter(!is.na(X1), !is.na(X2))
  )
  
}
  