#!/usr/bin/bash

today=$(date +''%Y%m%d'')
wd=~/projects/viewpointer/  # Set the working directory

cd ${wd} || exit

# Python script to scrape the data from Viewpoint
venv/bin/python3 -u get-withinday-listings.py 2>&1 | tee -a logs/console/"${today}".log

# Cleanup the scraped data, re-do the analysis
Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee -a logs/console/"${today}".log

# Updated public facing analysis
update-public.sh | tee -a logs/console/"${today}".log


