from configparser import ConfigParser
import viewpoint as vp

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
session.explicitly_wait(2)
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
session.scrape_index()

# Close everything at the end
session.quit()
