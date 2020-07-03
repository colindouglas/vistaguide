# Nova Scotia Real Estate Listings

This is a collection of scripts to scrape and analyze Nova Scotia real estate listings

* **`/data/`** contains some postal code data. The full data set is no longer included in the repo
* **`01-scrape-new-today.py`** uses the Viewpoint class in `viewpoint.py` to scrape all of the new listings posted recently
* **`02-retry-failures.py`** retries all of the pages that failed yesterday
* **`03-cleanup-today.R`** performs one time data cleanup that is CPU- or API-intensive. For example, it performs OSM lookup on new addresses to prevent duplicate API calls
* **`04-tidy-and-combine.R`** performs less intensive data cleanup, and combines all of the rows into one big data set.
* **`05-render-markdown.R`** generates the R Markdown report (`analysis.Rmd`) in both HTML and markdown format. The rendered report is available at [colindougl.as/real-estate](https://colindougl.as/real-estate/)
* **`pricing-model.R`** is an overly complex linear model to estimate sale prices that shouldn't be taken seriously
* **`sentiment-analysis.R`** performs some rudimentary sentiment analysis on the listing description, there's nothing interesting in there
* **`setup.R`** contains data on postal codes and color coding, as well as some helper functions for data cleanup
* **`vistaguide.sh`** is a bash script that glues it all together
