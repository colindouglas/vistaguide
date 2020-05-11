from selenium import webdriver
from selenium.common import exceptions as sce
from datetime import datetime
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.firefox.options import Options
from bs4 import BeautifulSoup
import re
import time
import os
from numpy import random as npr

############ THIS IS THE LOGGING BRANCH ################
# Function to randomly wait while printing a message about why it's waiting
# Wait times are normally distributed
def wait(message: chr = '', mean: float = 2, sd: float = 1) -> None:
    wt = npr.normal(loc=mean, scale=sd)
    if wt < 0.5:
        wt = 1 - wt
    print('[{dt}] Waiting for {:.1f} secs: {message}'.format(wt,
                                                             message=message,
                                                             dt=datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
    time.sleep(wt)
    return None


# Finds the next unused filename with the format baseYYYMMDDI.csv
# e.g., listing-202004051.csv for the second output of April 5, 2020
def next_filename(base: chr = 'listing_') -> chr:
    i = 0
    path = '{base}{dt}{i}.csv'.format(base=base, dt=datetime.now().strftime('%Y%m%d'), i=i)
    while os.path.exists(path):
        i += 1
        path = '{base}{dt}{i}.csv'.format(base=base, dt=datetime.now().strftime('%Y%m%d'), i=i)
    return path


class Viewpoint(webdriver.Firefox):
    # Function to start the web scraper and login with a username and password
    # Returns the Selenium driver object, which gets passed to subsequent functions
    def __init__(self, username, password, headless=True):

        # Set a Firefox profile so the print window doesn't mess things up
        # I'm not sure if this is necessary in headless mode but it doesn't break it so whatever
        profile = webdriver.FirefoxProfile()
        profile.set_preference("print.always_print_silent", True)
        profile.set_preference("print.show_print_progress", False)

        # Run Firefox headless so it can hide in the background
        options = Options()
        if headless:
            options.headless = True

        _LOGIN_URL = 'https://www.viewpoint.ca/user/login#!/new-today-list/'
        # Init the webdriver with the options and Firefox profile defined above
        # If 'geckodriver' isn't in the path, just an explicitly location
        super().__init__(profile,
                         options=options,
                         log_path='logs/geckodriver.log')

        # List of URLS that failed
        self.failed = list()

        # Set the window larger so everything stays on screen
        self.set_window_position(0, 0)
        self.set_window_size(1920, 1080)
        wait('Starting Firefox', 5)

        # Open the login URL and log in
        self.get(_LOGIN_URL)
        wait('Opening Viewpoint login', 2)

        # Fill in username and password and click on the button
        self.find_element_by_name('email').send_keys(username)
        self.find_element_by_name('password').send_keys(password)
        self.find_element_by_class_name('big').click()
        wait('Logging in to Viewpoint', 5)

    def __str__(self):
        # Print the window title
        return 'Viewpoint: ' + BeautifulSoup(self.page_source, 'html.parser').title.text.strip()

    # A function to click on a property 'button' (found via Selenium) and change focus to the popup
    # It then clicks on the 'print' button, closes the original popup, and changes focus to the print window
    # The print window is much easier to scrape than the 'pretty' version that pops up originally
    def open(self, button):
        # Remember which window is focused at the start
        index_window = self.current_window_handle

        # Shift click in the button
        ActionChains(self).key_down(Keys.SHIFT).click(button).key_up(Keys.SHIFT).perform()
        wait('Shift+clicked on property button', 5)

        # If there's a newly opened window, switch to it
        new_window = list({x for x in self.window_handles} - {index_window})
        if new_window:
            self.switch_to.window(new_window[0])
            wait('Switched focus to popup window', 5)

        # If it's failed previously, skip it
        if self.current_url in self.failed:
            wait('URL has already failed. Skipping ' + self.current_url, 2)
            return False

        # Click on the print button
        try:
            self.find_element_by_class_name('cutsheet-print').click()
            wait('Clicked on print button', 2)
        except sce.NoSuchElementException:
            wait('No print button! Skipping ' + self.current_url, 5)
            self.record_failure(self.current_url)
            return False

        # Close the 'pretty' window because we're going to scrape from the printable window
        self.close()
        wait('Closed pretty window', 2)

        # Switch context to the printable page
        try:
            new_window = list({x for x in self.window_handles} - {index_window})[0]
            self.switch_to.window(new_window)
            wait('Switched focus to printable window', 5)
            return True
        except (IndexError, sce.WebDriverException):
            wait('Couldn\'t open window. Skipping ' + self.current_url, 5)
            self.record_failure(self.current_url)
            return False

    # This is the function that does all of the scraping and writes it to the path in 'out'
    # The first argument is a Selenium driver that is currently focused on a the "Print"
    # view of a listing. The print view is much easier to scrape than the initial view
    def read(self, out='data/listings.csv'):

        if self.current_url in self.failed:
            wait('URL has already failed. Skipping ' + self.current_url, 2)
            return None

        # Run the listing page source through beautiful soup
        listing = BeautifulSoup(self.page_source, 'html.parser')

        # Take "ViewPoint.ca" out of the title
        try:
            title = re.sub(' - ViewPoint.ca', '', listing.title.text).strip()
        except AttributeError:
            title = ""

        # Sometimes the cutsheets aren't served properly, if that happens, bail
        if len(title) <= 10 or title == 'about:blank':
            wait_msg = '<{title}>: Address failed to load. Skipping {url}'
            wait(wait_msg.format(title=title, url=self.current_url), 5)
            self.record_failure(self.current_url)
            return None

        print('[{dt}] Scraping <{prop}>...'.format(prop=title,
                                                   dt=datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        try:
            desc = listing.find("div", {"class": "row-fluid printsmall"}).text.strip()
        except AttributeError:
            desc = "Missing description"

        # Record the time and the title of the window (which contains address and postal code)
        listing_row = [str(datetime.now()), title, self.current_url, desc]

        # Get the data table and write it to an ugly list
        for i, line in enumerate(listing.find_all('li', {'class': 'row'})):
            lines = ' '.join(list(str(line.text).split()))
            listing_row.append(lines)
        listing_row.append('\n')  # Add newline at the end to meet CSV criteria

        # Append the list to the output file 'out'
        with open(out, 'a') as file:
            tsv = '\t'.join(listing_row)
            file.write(tsv)
        wait('Finished scraping', 5)

    # This function goes through the listings in an index and scrapes them all and writes to the path in 'out'
    # The first argument (driver) should be a Selenium driver that is currently focused on the index
    # of a search or a dashboard. Pagination is handled in here as well.
    def scrape_all(self, out='data/listings.csv', handle=None):
        current_page = 1  # Page counter
        next_button = True  # Next button

        # Store which window is the index window
        # If the function had a handle argument, use that
        # Otherwise use the window with focus
        if handle is None:
            index_window = self.current_window_handle
        else:
            index_window = str(handle)

        # Go through all of the properties on this page of this page of the index and scrape them
        while bool(next_button):
            # Find all the different properties on the index page by matching the text on their buttons
            listings = list()
            button_strings = ['Entered', 'day on market', 'days on market']  # Find buttons with this text
            for button_string in button_strings:
                listings = listings + self.find_elements_by_partial_link_text(button_string)
            wait('Found {n} links on page {p}'.format(n=len(listings),
                                                      p=current_page
                                                      ), 5)

            # Click on each of the buttons and scrape the resulting data
            for i, listing in enumerate(listings):
                wait('Starting property #{p} on page {page}'.format(p=i+1, page=current_page), 2)
                # Try to open the window for each listing
                try:
                    window_opened = self.open(listing)
                except sce.WebDriverException:
                    wait('Failed to open listing popup window', 4)
                    continue

                # If the window was opened, read the window
                if window_opened:
                    self.read(out=out)
                    self.close()
                    wait('Finished with property #{p} on page {page}'.format(p=i+1, page=current_page), 5)

                # Switch back to the index to prepare for the next listing
                self.switch_to.window(index_window)
                wait('Switched to index window', 2)

            # Switch back to the index window
            self.switch_to.window(index_window)

            # Check if there's a next button, and click on it if it exists
            next_button = self.next_button()
            if bool(next_button):
                next_button.click()
                current_page += 1
                wait('Switching to page {page}'.format(page=current_page), 5)
            else:  # If we're on the last page, print a message and stop
                print('All finished after page', current_page)
                break

    # Check if there's a next button on this page
    # Return the button object if it exists, otherwise return false
    def next_button(self):
        try:
            out = self.find_element_by_link_text('NEXT »')
        except sce.NoSuchElementException:
            out = False
            wait('No next button detected. Must be done!')
        return out

    # If a URL doesn't work, record it to a log file and within the Viewpoint object
    def record_failure(self, url, path=None):
        if path is None:
            path = 'logs/{dt}_failed.log'.format(dt=datetime.now().strftime('%Y%m%d'))
        self.failed.append(self.current_url)
        with open(path, 'a') as file:
            file.write(url + '\n')

    # This function takes a list of URLs and tries to scrape each one
    def scrape(self, urls, path):
        urls = list(set(urls))  # Keep only the unique URLs

        # Printable pages are scraped using the vp.read() function
        # This is the trivial case of simply re-trying
        for url in urls:
            if url in self.failed:
                print('Already failed:', url)
                continue
            if 'cutsheet' in url:
                self.get(url)
                self.read(path)

        # If the URL is the path to a 'pretty' listing page, we need to switch to the printable version first
        # This adds a lot more steps
            elif 'property' in url:
                self.get(url)
                main_window = self.current_window_handle
                # --- Switch to the printable window
                # Try to click on the print button
                try:
                    self.find_element_by_class_name('cutsheet-print').click()
                    wait('Clicked on print button', 2)
                except sce.NoSuchElementException:
                    wait('No print button! Skipping ' + self.current_url, 5)
                    self.record_failure(self.current_url)
                    continue

                # Switch context to the printable page
                try:
                    new_window = list({x for x in self.window_handles} - {main_window})[0]
                    print("Windows open:", self.window_handles)
                    self.switch_to.window(new_window)
                    wait('Switched focus to printable window', 5)
                except (IndexError, sce.WebDriverException):
                    wait('Couldn\'t open window. Skipping ' + self.current_url, 5)
                    self.record_failure(self.current_url)
                    continue

                # --- End of switching to printable window
                self.read(path)
                self.switch_to.window(main_window)
                self.close()
            else:
                print('Don\'t know how to handle:', url)
