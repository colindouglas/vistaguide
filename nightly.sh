#!/usr/bin/bash

today=$(date +''%Y%m%d'')

venv/bin/python3 get-new-today.py > logs/"${today}"_withinday-anystatus.log 2>&1 | tee logs/"${today}"_cleanup.log
# venv/bin/python3 get-new-today.py > logs/"${today}"_new-today.log

Rscript --no-save --no-restore --verbose listing-cleanup.R 2>&1 | tee logs/"${today}"_cleanup.log