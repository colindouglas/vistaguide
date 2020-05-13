library(tidyverse)
library(patchwork)
source("setup.R")
# source("sentiment-analysis.R") # For using prices predicted by the sentiment of the description. Not useful


mlaw <- 0.5  # Weighting for MLA sqft number
train_on <- "sold" # One of "sold", "everything", or a fraction < 1.0


listings <- read_csv("data/listings-clean.csv") %>%
  distinct(pid, status, price, .keep_all = TRUE) %>%
  filter(price < 1000000, sqft_mla > 400,
         type %in% c("Single Family", "Condominium"),
         loc_bin != "Rest of Province") %>%
  rowwise() %>%
  mutate(sqft_dummy = max(0, (sqft_mla*mlaw + sqft_tla*(1-mlaw) - 750)),
         is_peninsula = loc_bin == "Halifax Peninsula",
         condo_fee_sqft = ifelse(is.na(condo_fee), 0, condo_fee/sqft_mla),
         assessment_in_thousands = ifelse(is.na(assessment) | assessment > 2E6, 0, assessment/1000),
         is_nice = grepl("69", address) | grepl("69", unit),
         style_bin = case_when(
           style %in% c("Condo Apartment") ~ "Apartment",
           style %in% c("Townhouse", "Condo Townhouse", "Semi-Detached") ~ "Shared Wall",
           style %in% c("Detached") ~ "Detached",
           TRUE ~ style
         )
         #desc_words = str_count(description, '\\w+'), # Words in description, not useful
         #loc_bin = ifelse(loc_bin == "Halifax Peninsula", peninsula_codes[postal_first], loc_bin) # Split the peninsula into smaller areas
         ) %>%
  ungroup() %>%
  mutate(building_age = ifelse(is.na(building_age), mean(building_age, na.rm = TRUE), building_age))


# Set up training and validation sets' ------------------------------------

# Train on "Sold" listings, test against "for sale" listings
if (train_on == "sold") {
  training_set <- listings %>%
    filter(status == "Sold")
  
  test_set <- listings %>%
    filter(status == "For Sale") %>%
    distinct(mls_no, pid, .keep_all = TRUE)
  # Train against everything, test against everything
} else if (train_on == "everything") {
  test_set <- training_set <- listings
  
  # Train on some fraction, then test on the remaining
} else if (is.numeric(train_on) & between(train_on, 0.5, 1)) {
  training_set <- listings %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    sample_frac(size = train_on)
  
  test_set <- listings %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    anti_join(training_set)
  
  
} else {
  error("Don't know how to train like that!")
}

complex_form <- price ~ loc_bin*(sqft_dummy + days_on_market) + style_bin + building_age  + assessment_in_thousands + is_nice

complex_model <- training_set %>%
  lm(complex_form, data = .)

dumb_model <- training_set %>%
  lm(price ~ loc_bin:sqft_tla, data = .)

test_set <- test_set %>%
  mutate(price = price,
         complex_prd = predict(complex_model, test_set), # Prediction by complex model
         dumb_prd = predict(dumb_model, test_set),  # Prediction by simple model
         xsv = complex_prd - price, # Excess value
         xsv_pct = xsv / price, # Excess value %
         xsv_z = (xsv_pct - mean(xsv_pct, na.rm = TRUE))/sd(xsv_pct, na.rm = TRUE)) # Z-score of excess value


complex_model_fig <- test_set %>%
  ggplot(aes(x = price, y = complex_prd)) +
  geom_point(aes(color = loc_bin), na.rm = TRUE, alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0, lty = 2) +
  scale_color_discrete(name = "", guide = FALSE) +
  scale_x_continuous(name = "Asking Price", labels = scales::dollar) +
  scale_y_continuous(name = "Predicted Sale Price", labels = scales::dollar) +
  ggtitle("Complex Model", 
          subtitle = paste0("RMS of Residuals: $", round(sqrt(mean(complex_model$residuals^2)), 0)))

dumb_model_fig <- test_set %>%
  ggplot(aes(x = dumb_prd, y = price)) +
  geom_point(aes(color = loc_bin), na.rm = TRUE, alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0, lty = 2) +
  scale_color_discrete(name = "") +
  scale_x_continuous(name = "Asking Price", labels = scales::dollar) +
  scale_y_continuous(name = NULL, labels = NULL) +
  ggtitle("Dumb Model", 
          subtitle = paste0("RMS of Residuals: $", round(sqrt(mean(dumb_model$residuals^2)), 0)))


model_figs <- complex_model_fig + dumb_model_fig
model_figs


