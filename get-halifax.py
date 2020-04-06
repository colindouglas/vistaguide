import keyring
import viewpoint as vp

# What username to login with?
with open('.username', 'r') as file:
    username = file.read()

# Find the next available filename
path = vp.next_filename("data/listings_")

# Log into ViewPoint
session = vp.Viewpoint(
    username=username,
    password=keyring.get_password("viewpoint", username)
)

# Open the Dashboard for a text list
session.find_element_by_link_text('DASHBOARD').click()
vp.wait('Opening dashboard', 5)

# Click on the 'Saved Searches' link
session.find_element_by_link_text('SAVED SEARCHES').click()
vp.wait('Opening Saved Searches index', 3)

# Open the previously saved 'Halifax in the Last Week' search
session.find_element_by_partial_link_text('Halifax in the Last Week').click()
vp.wait('Opening relevant saved search', 3)

# Scrape all of the data from the opened index
session.scrape_all(out=path)

# Close everything at the end
session.quit()
