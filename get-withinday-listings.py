from configparser import ConfigParser
import viewpoint as vp
 
# Read credentials from config file (./config.txt)
config = ConfigParser()
config.read('config.txt')

# Find the next available filename
path = vp.next_filename("data/listings_")

for x in range(0, 3):
    try:
        # Log into ViewPoint
        session = vp.Viewpoint(
            username=config['credentials']['username'],
            password=config['credentials']['password']
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

        # If this works, record that there were no errors
        error = None

    # Sometimes there are random server errors. If they happen, bail print the error
    # The loop will start again
    except Exception as error:
        vp.wait("Error in scraping listings", 60 * 10)  # Wait 10 minutes if there's an error
        print(error)  # Print the error for logging

    # If there wasn't an error, break out of the loop and don't restart it
    if not error:
        break

# Close everything at the end
session.quit()
