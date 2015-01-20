#!/bin/bash

# ----------------------------------------------------
# Wrapper to remove all BigQuery tables in a dataset matching certain regexp
# Based on https://cloud.google.com/bigquery/bq-command-line-tool, 
# should be installed prior to usage

# Usage `./rm_tables.sh <dataset> '<regexp>'`
# i. e. `./rm_tables.sh adform_con '_tmp.*'`


TABLES=$(bq ls $1 | grep $2 | awk '{print $1;}')

for TABLE in $TABLES
	do
		echo "Deleting $1.$TABLE"
		bq rm -f "$1.$TABLE"
	done

