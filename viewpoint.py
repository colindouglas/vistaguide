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
import logging
from logging.handlers import TimedRotatingFileHandler
from numpy.random import normal as rand_norm

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
    def __init__(self, username, password, headless=True, log='logs/viewpointer.log'):

        # Setup the logger
        self.logger = logging.getLogger('viewpointer')
        formatter = logging.Formatter('%(asctime)7s - %(name)s - %(levelname)s - %(message)s')

        # Write a log file for everything DEBUG and up
        self.logger.setLevel(logging.DEBUG)

        # Rotate the log files at midnight, keep a week's worth of logging
        fh = TimedRotatingFileHandler(filename=log, when='midnight', backupCount=7)
        fh.setFormatter(formatter)
        self.logger.addHandler(fh)

        # For console output, only print INFO and up
        ch = logging.StreamHandler()
        ch.setFormatter(formatter)
        ch.setLevel(logging.INFO)
        self.logger.addHandler(ch)

        self.logger.debug('Initializing Viewpointer session')
        self.logger.debug('Logging to ' + str(log))

        # Set a Firefox profile so the print window doesn't mess things up
        # I'm not sure if this is necessary in headless mode but it doesn't break it so whatever
        profile = webdriver.FirefoxProfile()
        profile.set_preference("print.always_print_silent", True)
        profile.set_preference("print.show_print_progress", False)
        self.logger.debug('Starting up Firefox')

        # Run Firefox headless so it can hide in the background and not steal focus
        options = Options()
        if headless:
            options.headless = True
            self.logger.debug('Running headless')
        else:
            self.logger.debug('Not running headless')

        _LOGIN_URL = 'https://www.viewpoint.ca/user/login#!/new-today-list/'
        # Init the webdriver with the options and Firefox profile defined above
        super().__init__(profile,
                         options=options,
                         log_path='logs/geckodriver.log')

        self.failed = list()  # URLs that have failed
        self.worked = list()  # URLs that have worked
        self.index_window = None  # The window handle of the "index" window with all the listings

        # Set the window larger so everything stays on screen
        self.set_window_position(0, 0)
        self.set_window_size(1920, 1080)
        self.logger.debug('Changed Firefox window size')
        self.implicitly_wait(5)

        # Open the login URL and log in
        self.logger.debug('Opening Viewpoint login URL: ' + str(_LOGIN_URL))
        self.get(_LOGIN_URL)
        self.implicitly_wait(2)

        # Fill in username and password and click on the button
        self.logger.info('Logging in with username \'{0}\''.format(username))
        self.find_element_by_name('email').send_keys(username)
        self.find_element_by_name('password').send_keys(password)
        self.find_element_by_class_name('big').click()
        self.implicitly_wait(5)
        self.logger.debug('Successfully logged in')

    def __str__(self):
        # Print the window title
        return 'Viewpoint: ' + BeautifulSoup(self.page_source, 'html.parser').title.text.strip()

    ''' 
    A function to click on a property 'button' (found via Selenium) and change focus to the popup
    It then clicks on the 'print' button, closes the original popup, and changes focus to the print window
    The print window is much easier to scrape than the 'pretty' version that pops up originally
    '''
    def navigate_to_printable(self, button):

        self.logger.debug('Navigating to printable property screen')
        self.implicitly_wait(5)

        # Remember which window is focused at the start
        self.index_window = self.current_window_handle
        self.logger.debug('Remembering index window: ' + str(self.index_window))

        # Shift click in the button to open it in a new window
        self.logger.debug('Handles before Shift+Click: ' + str(self.window_handles))
        ActionChains(self).key_down(Keys.SHIFT).click(button).key_up(Keys.SHIFT).perform()
        self.logger.debug('Handles after Shift+Click: ' + str(self.window_handles))
        self.explicitly_wait(2)

        # Check if a new window opened up
        self.logger.debug("Checking for new popup window...")
        new_window = list({x for x in self.window_handles} - {self.index_window})

        if new_window:
            self.logger.debug('Found new window: ' + str(new_window))
            self.switch_to.window(new_window[0])
            self.log_windows()
            self.implicitly_wait(5)
            popup_url = self.current_url
        else:
            self.logger.warning('No popup window detected')
            self.log_windows()
            return False

        # If it's failed previously, skip it
        if self.current_url in self.failed:
            self.logger.info('URL already failed. Skipping ' + self.current_url)
            self.implicitly_wait(5)
            return False

        # If it's already been scraped today, skip it
        if self.current_url in self.worked:
            self.logger.info('URL already scraped. Skipping ' + self.current_url)
            self.implicitly_wait(5)
            return False

        # Click on the print button and close the pretty window
        self.logger.debug('Looking for a print button...')
        try:
            self.find_element_by_class_name('cutsheet-print').click()
            self.logger.debug('Detected a print button and clicked.')
        except sce.NoSuchElementException:
            self.logger.warning('No print button detected. Skipping ' + self.current_url)
            self.record_failure(self.current_url)
            return False
        finally:
            self.close()
            self.logger.debug('Closed pretty window {0}: {1}'.format(self.current_window_handle, self.current_url))
            self.explicitly_wait(2)

        # Switch context to the printable page
        try:
            new_window = list({x for x in self.window_handles} - {self.index_window})[0]
            self.switch_to.window(new_window)
            self.logger.debug('Focused on print window {0}: {1}'.format(self.current_window_handle, self.current_url))
            self.implicitly_wait(5)
            self.worked.append(popup_url)
            return True
        except (IndexError, sce.WebDriverException):
            self.logger.warning('Couldn\'t open window. Skipping ' + self.current_url)
            self.implicitly_wait(5)
            self.record_failure(self.current_url)
            self.logger.debug('Closing window {0}: {1}'.format(self.current_window_handle, self.current_url))
            self.close()
            return False

    '''
    This is the function that does all of the scraping and writes it to the path in 'out'
    It should be called on a Selenium driver that is currently focused on a the "Print"
    view of a listing. The print view is much easier to scrape than the initial view
    '''

    def read_printable(self, out='data/listings.csv'):

        # If it's already failed, don't bother trying it
        if self.current_url in self.failed:
            self.logger.info('URL has already failed. Skipping ' + self.current_url)
            self.implicitly_wait(2)
            return None

        # Run the listing page source through beautiful soup
        listing = BeautifulSoup(self.page_source, 'html.parser')

        # Take "ViewPoint.ca" out of the title
        try:
            title = re.sub(' - ViewPoint.ca', '', listing.title.text).strip()
        except AttributeError:
            title = ""
            self.logger.warning('No page title found')

        # Sometimes the cutsheets aren't served properly, if that happens, bail
        if len(title) <= 10 or title == 'about:blank':
            wait_msg = '<{title}>: Address failed to load. Skipping {url}'
            self.logger.warning(wait_msg.format(title=title, url=self.current_url))
            self.implicitly_wait(5)
            self.record_failure(self.current_url)
            return None
        self.logger.info('Scraping <{prop}>...'.format(prop=title))
        try:
            desc = listing.find("div", {"class": "row-fluid printsmall"}).text.strip()
        except AttributeError:
            desc = "Missing description"
            self.logger.warning('Missing description for <{0}>'.format(title))

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
        self.logger.debug('Successfully scraped <{0}>'.format(title))
        self.implicitly_wait(5)

    # This function goes through the listings in an index and scrapes them all and writes to the path in 'out'
    # The first argument (driver) should be a Selenium driver that is currently focused on the index
    # of a search or a dashboard. Pagination is handled in here as well.
    def scrape_index(self, out='data/listings.csv', handle=None):
        self.logger.debug('Scraping all listings...')
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
            self.explicitly_wait(3)  # Wait to prevent duplicates
            for button_string in button_strings:
                listings = listings + self.find_elements_by_partial_link_text(button_string)
            self.logger.info('Found {n} links on page {p}'.format(n=len(listings),
                                                                  p=current_page
                                                                  ))
            self.implicitly_wait(5)

            # Click on each of the buttons and scrape the resulting data
            for i, listing in enumerate(listings):
                self.logger.debug('Starting property #{p} on page {page}'.format(p=i + 1, page=current_page))
                self.implicitly_wait(2)
                # Try to open the window for each listing
                try:
                    window_opened = self.navigate_to_printable(listing)
                except sce.WebDriverException:
                    window_opened = False
                    self.logger.warning(
                        'Failed to open property #{p} on page {page}'.format(p=i + 1, page=current_page)
                    )
                    self.implicitly_wait(4)

                # If the window was successfully opened, read the listing
                if window_opened:
                    self.read_printable(out=out)
                    self.close()
                    self.logger.debug('Finished with property #{p} on page {page}'.format(p=i + 1, page=current_page))
                    self.implicitly_wait(5)

                # Switch back to the index to prepare for the next listing
                self.switch_to.window(self.index_window)
                self.logger.debug('Switched to index window ' + str(self.index_window))
                self.implicitly_wait(2)

            # Switch back to the index window
            self.switch_to.window(index_window)

            # Check if there's a next button, and click on it if it exists
            next_button = self.next_button()
            if bool(next_button):
                next_button.click()
                current_page += 1
                self.logger.debug('Switching to page {page}'.format(page=current_page))
                self.implicitly_wait(5)
            else:  # If we're on the last page, print a message and stop
                self.logger.info('All finished after page ' + str(current_page))
                break

    # Check if there's a next button on this page
    # Return the button object if it exists, otherwise return false
    def next_button(self):
        try:
            out = self.find_element_by_link_text('NEXT »')
            self.logger.debug('Found next button on ' + str(self.current_url))
        except sce.NoSuchElementException:
            out = False
            self.logger.debug('No next button detected. Must be done!')
            self.implicitly_wait(2)
        return out

    # If a URL doesn't work, record it to a log file and within the Viewpoint object
    def record_failure(self, url, path=None):
        if path is None:
            path = 'logs/{dt}_failed.log'.format(dt=datetime.now().strftime('%Y%m%d'))
        self.failed.append(url)
        self.logger.warning('Recording failed url: ' + str(url))
        with open(path, 'a') as file:
            file.write(url + '\n')

    # This function takes a list of URLs and tries to scrape each one
    def scrape_urls(self, urls, path):
        urls = list(set(urls))  # Keep only the unique URLs

        # Printable pages are scraped using the vp.read() function
        # This is the trivial case of simply re-trying
        for url in urls:
            if url in self.failed:
                self.logger.info('Already failed:', url)
                continue
            if 'cutsheet' in url:
                self.get(url)
                self.read_printable(path)

        # If the URL is the path to a 'pretty' listing page, we need to switch to the printable version first
        # This adds a lot more steps
            elif 'property' in url:
                self.get(url)
                main_window = self.current_window_handle
                # --- Switch to the printable window
                # Try to click on the print button
                try:
                    self.find_element_by_class_name('cutsheet-print').click()
                    self.logger.debug('Clicked on print button')
                    self.implicitly_wait(2)
                except sce.NoSuchElementException:
                    self.logger.warning('No print button! Skipping ' + self.current_url)
                    self.implicitly_wait(5)
                    self.record_failure(self.current_url)
                    continue

                # Switch context to the printable page
                try:
                    new_window = list({x for x in self.window_handles} - {main_window})[0]
                    self.logger.debug("Windows open:", self.window_handles)
                    self.switch_to.window(new_window)
                    self.logger.debug('Switched focus to printable window')
                    self.implicitly_wait(5)
                except (IndexError, sce.WebDriverException):
                    self.logger.warning('Couldn\'t open window. Skipping ' + self.current_url)
                    self.implicitly_wait(5)
                    self.record_failure(self.current_url)
                    continue

                # --- End of switching to printable window
                self.read_printable(path)
                self.switch_to.window(main_window)
                self.close()
            else:
                self.logger.warning('Don\'t know how to handle:' + url)

    # Implicitly wait a normally distributed amount of time above 'min_'
    def implicitly_wait_rand(self, min_):
        st_dev = 1
        wt = abs(rand_norm(loc=0, scale=st_dev))
        self.logger.debug('Implicitly waiting {0:.1f} secs'.format(wt))
        self.implicitly_wait(wt)
        return None

    # Explicitly wait a normally distributed amount of time above 'shortest'
    def explicitly_wait(self, shortest):
        st_dev = 2
        wt = abs(rand_norm(loc=0, scale=st_dev)) + shortest
        self.logger.debug('Explicitly waiting {0:.1f} secs'.format(wt))
        time.sleep(wt)
        return None

    # This function logs the windows that are currently open to the logger at level 'DEBUG'.
    # It starts with the focused window, and switched back to the focused window at the end
    def log_windows(self):
        start_window = self.current_window_handle
        window_dict = {
            self.current_window_handle: "focus",
            self.index_window: "index",
        }
        self.logger.debug('Window {0} ({1}): {2}'.format(
            self.current_window_handle,
            window_dict.setdefault(self.current_window_handle, "unknown"),
            self.current_url))
        self.implicitly_wait(2)
        self.switch_to.window(start_window)
        self.logger.debug('Done of window logging, switching back to {0}'.format(start_window))





