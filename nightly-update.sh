#!/usr/bin/bash

today=$(date +''%Y%m%d'')

venv/bin/python3 get-withinday-anystatus.py >> logs/"${today}"_withinday.log 2>&1
# venv/bin/python3 get-new-today.py > logs/"${today}"_new-today.log

Rscript --no-save --no-restore --verbose listing-cleanup.R  >>  logs/"${today}"_cleanup.log 2>&1