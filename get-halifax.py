import keyring
import viewpoint as vp

username = 'colindouglas@gmail.com'

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

# Scrape all of the links from the 'New Today' index
vp.scrape_all(session, out='data/listings.csv')
