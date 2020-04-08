#!/usr/bin/bash


today=$(date +''%Y%m%d'')

cd /home/colin/projects/viewpointer/
venv/bin/python3 -u get-withinday-anystatus.py 2>&1 | tee -a logs/"${today}"_withinday.log
# venv/bin/python3 get-new-today.py > logs/"${today}"_new-today.log

Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee -a  logs/"${today}"_cleanup.log
