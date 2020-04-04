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
vp.random_wait('Open dashboard', 3)

# Scrape all of the links from the 'New Today' index
vp.scrape_all(session, out='data/listings.csv')
