# Nova Scotia Real Estate Listings

This is a collection of scripts to scrape and analyze Nova Scotia real estate listings

* **/data/** contains the cleaned up listing data (in long form) as well as some postal code data
*	**analysis.Rmd** is the Rmarkdown file that does most of the analysis work. The rendered report is as [colindougl.as/vp/](https://colindougl.as/vp/)
* **csv_to_tsv.R** does some cleanup on malformed data that is sometimes served
* **get-withinday-listings.py** is a script that downloads the results of a custom saved search
*	**listing-cleanup.R** is a script to convert the scraped data to long format
* **pricing-model.R** is an overly complex linear model to estimate sale prices that shouldn't be taken seriously
* **sentiment-analysis.R** performs some rudimentary sentiment analysis on the listing description, there's nothing interesting in there.
* **setup.R** contains data on postal codes and color coding
* **viewpoint.py** does all of the hard work. An extension of the Selenium webdriver class designed to help navigate and scrape a real estate listings website
* **viewpointer.sh** is a bash script to glue it all together
