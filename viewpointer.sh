#!/usr/bin/bash

today=$(date +''%Y%m%d'')

cd /home/colin/projects/viewpointer/

venv/bin/python3 -u get-withinday-listings.py 2>&1 | tee -a logs/"${today}"_withinday.log

Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee -a  logs/"${today}"_cleanup.log

scp /home/colin/projects/viewpointer/analysis.html 192.168.0.100:/var/www/viewpoint.html
