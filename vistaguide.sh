#!/usr/bin/bash

today=$(date +''%Y%m%d'')
wd=/home/colin/projects/vistaguide  # Set the working directory
logfile=${wd}/logs/console/"${today}".log


# Send stdout and stderr to the logfile
exec >> ${logfile}
exec 2>&1

echo Starting vistaguide update at $(date +'%Y-%B-%d %-H:%M:%S')
echo Logging to ${logfile}

cd ${wd} || exit

# Scrape today's data from ViewPoint
venv/bin/python3 -u 01-scrape-new-today.py

# Retry yesterday's failures
venv/bin/python3 -u 02-retry-failures.py 

# Cleanup today's newly scraped data
Rscript --no-save --no-restore --verbose 03-cleanup-scraped.R

# No need to run 04, it's run from 03

# Render the markdown file
Rscript --no-save --no-restore --verbose 05-render-markdown.R

# Deploy to web
source 06-deploy.sh 

