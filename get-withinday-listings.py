from configparser import ConfigParser
import viewpoint as vp
from datetime import datetime, timedelta


# Read credentials from config file
config = ConfigParser()
config.read('config.txt')

# ./config.txt should be a text file with the structure:
'''
[credentials]

username = YOUR_email@domain.com
password = hunter2
'''

# Find the next available filename
path = vp.next_filename("data/listings_")

# Log into ViewPoint
session = vp.Viewpoint(
    username=config['credentials']['username'],
    password=config['credentials']['password'],
    headless=True
)

# Open the Dashboard for a text list
session.logger.debug('Opening the dashboard')
session.find_element_by_link_text('DASHBOARD').click()
session.explicitly_wait(5)

# Click on the 'Saved Searches' link
session.logger.debug('Opening saved searches')
session.find_element_by_link_text('SAVED SEARCHES').click()
session.explicitly_wait(5)

# Open the previously saved 'Halifax in the Last Week' search
session.find_element_by_partial_link_text('Everything WithinDay').click()
session.implicitly_wait(3)

# Scrape all of the lines
session.scrape_index(out=path)

session.logger.info('Starting yesterday\'s failures')
# Get the failed URLs from yesterday
yesterday = datetime.now() - timedelta(days=0)
failed_path = 'logs/{dt}_failed.log'.format(dt=yesterday.strftime('%Y%m%d'))
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
    session.scrape_urls(urls, path)
    session.logger.info("Finished with yesterday's failures")

# Close everything at the end
session.quit()
