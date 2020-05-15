from configparser import ConfigParser
import viewpoint as vp
from datetime import datetime, timedelta
import os

# Read credentials from config file
config = ConfigParser()
config.read('config.txt')

# Find the next available filename
path = vp.next_filename("data/listings_")

# Log into ViewPoint
session = vp.Viewpoint(
    username=config['credentials']['username'],
    password=config['credentials']['password'],
    headless=True
)

session.explicitly_wait(5)

session.logger.info('Starting yesterday\'s failures')
# Get the failed URLs from yesterday
yesterday = datetime.now() - timedelta(days=1)
failed_path = 'logs/failed/{dt}.log'.format(dt=yesterday.strftime('%Y%m%d'))
urls = list()

# Read the file in, if it exists
try:
    with open(failed_path, 'r') as log:
        for line in log:
            urls.append(line)
except FileNotFoundError:
    session.logger.info("No failures found in path: {0}".format(failed_path))

# Scrape each of the URLs from the list of failures
# If there are URLs in it, try each one
if len(urls) > 0:
    session.scrape_urls(urls)
    session.logger.info("Finished with yesterday's failures")
    os.rename(failed_path, failed_path + ".done")
    session.logger.info("Renaming: {0} >> {0}.done".format(failed_path))


# Close everything at the end
session.quit()
