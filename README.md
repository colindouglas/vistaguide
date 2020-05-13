# Viewpointer

This is a collection of scripts to scrape and analyze Nova Scotia real estate listings from Viewpoint.ca.

* **/data/** contains the cleaned up listing data (in long form) as well as some postal code data
*	**analysis.Rmd** is the Rmarkdown file that does most of the analysis work. The rendered report is as [colindouglas.github.io/viewpointer.html](https://colindouglas.github.io/viewpointer.html)
* **csv_to_tsv.R** does some cleanup on malformed data that is sometimes served by ViewPoint.ca
* **get-withinday-listings.py** is a script that downloads the results of a custom ViewPoint.ca saved search
*	**listing-cleanup.R** is a script to convert the scraped data to long format. It's not very efficient
* **pricing-model.R** is an overly complex linear model to estimate sale prices based on list prices
* **sentiment-analysis.R** performs some rudimentary sentiment analysis on the listing description, there's nothing interesting in there.
* **setup.R** contains data on postal codes and color coding in the analysis.
* **viewpoint.py** does all of the hard work. An extension of the Selenium webdriver class designed to help navigate and scrape ViewPoint.ca 
* **viewpointer.sh** is a bash script to glue it all together