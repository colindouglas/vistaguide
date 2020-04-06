import viewpoint as vp
import keyring

# What username to login with?
with open('.username', 'r') as file:
    username = file.read()

# Find the next available filename
path = vp.next_filename("data/listings_")

# Log into ViewPoint
session = vp.Viewpoint(
    username,
    keyring.get_password("viewpoint", username)
)

# Open the Dashboard for a text list
session.find_element_by_link_text('DASHBOARD').click()
vp.wait('Open dashboard', 3)

# Scrape all of the data from the opened index
session.scrape_all(out=path)

# Close everything at the end
session.quit()
