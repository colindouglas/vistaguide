from selenium import webdriver
from datetime import datetime
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from bs4 import BeautifulSoup
import re
import time
import os
from numpy import random as npr

# Function to randomly wait while printing a message about why it's waiting
# Wait times are normally distributed
def random_wait(message='', mean=2, sd=1):
    wt = npr.normal(loc=mean, scale=sd)
    if wt < 0.5:
        wt = 1 - wt
    print('Waiting for {:.1f} secs: {message}'.format(wt, message=message))
    time.sleep(wt)

# Function to start the web scraper and login with a username and password
# Returns the Selenium driver object, which gets passed to subsequent functions
def login(username, password):
    profile = webdriver.FirefoxProfile()
    profile.set_preference("print.always_print_silent", True)
    profile.set_preference("print.show_print_progress", False)

    LOGIN_URL = 'https://www.viewpoint.ca/user/login#!/new-today-list/'

    # Start firefox, accept the login URL
    driver = webdriver.Firefox(profile)
    driver.maximize_window()
    random_wait('Starting Firefox', 5)
    driver.get(LOGIN_URL)
    random_wait('Opening Viewpoint login', 2)

    # Fill in username and password and click on the button
    driver.find_element_by_name('email').send_keys(username)
    driver.find_element_by_name('password').send_keys(password)
    driver.find_element_by_class_name('big').click()
    random_wait('Logging in to Viewpoint', 5)
    return driver


# A function to click on a property 'button' (found via Selenium) and change focus to the popup
# It then clicks on the 'print' button, closes the original popup, and changes focus to the print window
# The print window is much easier to scrape than the 'pretty' version that pops up originally
def open_listing(driver, button):
    # Remember which window is focused at the start
    index_window = driver.current_window_handle

    # Click on the button to open the window
    # button.click()
    # random_wait('Clicked on property button', 5)

    # Shift click in the button
    ActionChains(driver).key_down(Keys.SHIFT).click(button).key_up(Keys.SHIFT).perform()
    random_wait('Shift+clicked on property button', 5)

    # If there's a newly opened window, switch to it
    new_window = list({x for x in driver.window_handles} - {index_window})
    if new_window:
        driver.switch_to.window(new_window[0])
        random_wait('Switched to window', 3)

    # Click on the print button
    driver.find_element_by_class_name('cutsheet-print').click()
    random_wait('Clicked on print button', 2)

    # If the index is opening popup windows, close the 'pretty' window
    driver.close()
    random_wait('Closed pretty window', 2)



    # Switch context to the printable page
    new_window = list({x for x in driver.window_handles} - {index_window})[0]
    driver.switch_to.window(new_window)
    random_wait('Switched to printable window', 5)


def read_listing(driver, out='data/listings.csv'):
    # Run the listing page source through beautiful soup
    listing = BeautifulSoup(driver.page_source, 'lxml')

    # Record the time and the title of the window (which contains address and postal code)
    listing_row = [str(datetime.now()), listing.title.text, driver.current_url]

    print('Scraping listing...')
    for i, line in enumerate(listing.find_all('li', {'class': 'row'})):
        lines = ' '.join(list(str(line.text).split()))
        listing_row.append(lines)
    listing_row.append('\n')  # Add newline at the end to meet CSV criteria

    # Append the list to the output file 'out'
    with open(out, 'a') as file:
        file.write('\t'.join(listing_row))
    random_wait('Scraped <{0}>'.format(listing_row[1]), 5)


def scrape_all(driver, out='data/listings.csv', handle=None):
    if handle is None:
        index_window = driver.current_window_handle
    else:
        index_window = str(handle)

    # Download the first page
    first_page = BeautifulSoup(driver.page_source, 'lxml')

    # Figure out how many listings there are total
    # Because of the way the page loads, the source has many hidden "1 to 10 of X"
    # The last one in the list is relevant
    listing_count = re.findall('Showing 1 to [0-9]+ of [0-9]+', first_page.text)[-1].split()[-1]
    if listing_count:
        listing_count = int(listing_count)
    else:
        listing_count = 0

    # Count the total pages
    total_pages = listing_count // 10 + 1
    current_page = 1

    print('Found {n} total listings across {tp} pages'.format(n=listing_count, tp=total_pages))

    # Go through all of the properties on this page of this page of the index and scrape them
    while current_page <= total_pages:

        # Find all the different properties on the index page by matching
        properties = list()
        button_strings = ['Entered', 'day on market', 'days on market']  # Find buttons with this text
        for button_string in button_strings:
            properties = properties + driver.find_elements_by_partial_link_text(button_string)
        random_wait('Found {n} links on page {p}/{tp}'.format(n=len(properties),
                                                            p=current_page,
                                                            tp=total_pages),
                    5)

        # Click on each of the buttons and scrape the resulting data
        for i, property in enumerate(properties):
            random_wait('Starting property {p} on page {page}'.format(p=i+1, page=current_page), 2)
            open_listing(driver, property)
            read_listing(driver, out=out)
            driver.close()
            random_wait('Finished with property {p} on page {page}'.format(p=i+1, page=current_page), 5)
            driver.switch_to.window(index_window)
            random_wait('Switched to index window', 2)

        # Switch back to the index window
        driver.switch_to.window(index_window)

        # Click on the next button if we're not on the last page
        if current_page < total_pages:
            driver.find_element_by_link_text('NEXT »').click()
            current_page += 1
            random_wait('Switching to page {page}'.format(page=current_page), 5)
        else:  # If we're on the last page, print a message and stop
            print('All finished after page', current_page)
            break

def next_filename(base):
    i = 0
    path = '{base}{dt}{i}.csv'.format(base=base, dt=datetime.now().strftime('%Y%m%d'), i=i)
    while os.path.exists(path):
        i += 1
        path = '{base}{dt}{i}.csv'.format(base=base, dt=datetime.now().strftime('%Y%m%d'), i=i)
    return path

#TODO Close window at end
#TODO Scrape description as well