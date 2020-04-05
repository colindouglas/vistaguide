import keyring
import viewpoint as vp


with open('.username', 'r') as file:
    username = file.read()

# Login to Viewpoint, start a Selenium session
session = vp.login(
    username=username,
    password=keyring.get_password("viewpoint", username)
)

# Open the Dashboard for a text list
session.find_element_by_link_text('DASHBOARD').click()
vp.random_wait('Opening dashboard', 5)
session.find_element_by_link_text('SAVED SEARCHES').click()
vp.random_wait('Opening Saved Searches index', 3)
session.find_element_by_partial_link_text('Halifax in the Last Week').click()
vp.random_wait('Opening relevant saved search', 3)

# Find the next available filename
path = vp.next_filename("data/listings_")

# Scrape all of the data from the opened index
vp.scrape_all(session, out=path)

