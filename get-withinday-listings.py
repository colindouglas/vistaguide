from configparser import ConfigParser
import viewpoint as vp
from datetime import datetime, timedelta

# Read credentials from config file (./config.txt)
config = ConfigParser()
config.read('config.txt')

# Find the next available filename
path = vp.next_filename("data/listings_")

# Log into ViewPoint
session = vp.Viewpoint(
    username=config['credentials']['username'],
    password=config['credentials']['password'],
     headless=False
)

# Open the Dashboard for a text list
session.find_element_by_link_text('DASHBOARD').click()
vp.wait('Opening dashboard', 5)

# Click on the 'Saved Searches' link
session.find_element_by_link_text('SAVED SEARCHES').click()
vp.wait('Opening Saved Searches index', 3)

# Open the previously saved 'Halifax in the Last Week' search
session.find_element_by_partial_link_text('Everything WithinDay').click()
vp.wait('Opening relevant saved search', 3)

# Scrape all of the lines
session.scrape_all(out=path)

# Get the failed URLs from yesterday
yesterday = datetime.now() - timedelta(days=1)
failed_path = 'logs/{dt}_failed.log'.format(dt=yesterday.strftime('%Y%m%d'))
urls = list()

# Read the file in, if it exists
try:
    with open(failed_path, 'r') as log:
        for line in log:
            urls.append(line)
except FileNotFoundError:
    print("No failures found from yesterday!")

# Scrape each of the URLs from the list of failures
# If there are URLs in it, try each one
if len(urls) > 0:
    session.scrape(urls, path)

# Close everything at the end
session.quit()
