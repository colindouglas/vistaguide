#!/usr/bin/bash

# Set appropriate paths
source /home/colin/.bashrc

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
Rscript --no-save --no-restore --verbose 03-cleanup-today.R

# Cleanup the listing data
Rscript --no-save --no-restore --verbose 04-tidy-and-combine.R 

# Render the markdown file
Rscript --no-save --no-restore --verbose 05-render-markdown.R

# Deploy to web
./06-deploy.sh 

