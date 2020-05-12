#!/usr/bin/bash

today=$(date +''%Y%m%d'')

# Working directory
cd /home/colin/projects/viewpointer/

# Python script to scrape the data from Viewpoint
venv/bin/python3 -u get-withinday-listings.py 2>&1 | tee -a logs/console/"${today}".log

# Cleanup the scraped data, re-do the analysis
Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee -a logs/console/"${today}".log

# Upload the analysis HTML to a web server so it's accessible across the network
scp /home/colin/projects/viewpointer/analysis.html 192.168.0.100:/var/www/viewpoint.html | tee -a logs/console/"${today}".log
