#!/usr/bin/bash

today=$(date +''%Y%m%d'')
wd=~/projects/vistaguide/  # Set the working directory

cd ${wd} || exit

# Scrape the today's data from ViewPoint
venv/bin/python3 -u get-withinday-listings.py 2>&1 | tee -a logs/console/"${today}".log

# Retry yesterday's failures
venv/bin/python3 -u retry-failures.py 2>&1 | tee -a logs/console/"${today}".log

# Cleanup the listing data
Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee -a logs/console/"${today}".log

# Render the markdown file
Rscript --no-save --no-restore --verbose render-markdown.R 2>&1 | tee -a logs/console/"${today}".log



