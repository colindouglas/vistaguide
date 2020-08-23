library(tidyverse)
library(patchwork)
library(lme4)
source("setup-constants.R")
source("connect-db.R")
# source("sentiment-analysis.R") # For using prices predicted by the sentiment of the description. Not useful


mlaw <- 0.5  # Weighting for MLA sqft number
train_on <- "sold" # One of "sold", "everything", or a fraction < 1.0

# Get data from db --------------------------------------------------------
properties <- tbl(dbcon, "properties")
updates <- tbl(dbcon, "updates") 
geocode <- tbl(dbcon, "geocode")

sale_prices <- updates %>%
  left_join(properties, by = "prop_id") %>%
  left_join(geocode, by = "address") %>%
  filter(loc_bin != "Rest of Province", 
         !is.na(price),
         !is.na(sqft_tla),
         !is.na(sqft_mla)) %>%
  collect()


# Transform ---------------------------------------------------------------

listings_model <- sale_prices %>%
  distinct(pid, status, price, .keep_all = TRUE) %>%
  filter(price < 750000, #sqft_mla > 400,
         type %in% c("Single Family", "Condominium"),
         loc_bin != "Rest of Province") %>%
  rowwise() %>%
  mutate(
    sqft_dummy = case_when(
      sqft_mla == 0 | is.na(sqft_mla) ~ as.numeric(sqft_tla),
      sqft_tla == 0 | is.na(sqft_tla) ~ as.numeric(sqft_mla), 
      TRUE ~ max(0, (sqft_mla*mlaw + sqft_tla*(1-mlaw) - 750))),
    is_peninsula = loc_bin == "Halifax Peninsula",
    condo_fee = ifelse(is.na(condo_fee), 0, condo_fee),
    assessment_in_thousands = ifelse(is.na(assessment) | assessment > 2E6, 0, assessment/1000),
    style_bin = case_when(
      style %in% c("Condo Apartment") ~ "Apartment",
      style %in% c("Townhouse", "Condo Townhouse", "Semi-Detached") ~ "Shared Wall",
      style %in% c("Detached") ~ "Detached",
      TRUE ~ "Detached"),
    is_condo = style_bin == "Apartment",
    loc_bin = ifelse(loc_bin == "Halifax Peninsula", peninsula_codes[postal_first], loc_bin), # Split the peninsula into smaller areas
    floor = case_when(
      type != "Condominium" ~ 0,
      is.na(as.numeric(unit)) ~ 0,
      as.numeric(unit) < 100 ~ 0,
      TRUE ~ as.numeric(unit) %/% 100),
    agent = ifelse(is.na(word(compliments_of, 1, 2)), "Unknown", word(compliments_of, 1, 2))
  ) %>%
  ungroup() %>%
  mutate(building_age = ifelse(is.na(building_age), mean(building_age, na.rm = TRUE), building_age),
         parcel_size = case_when(
           is_condo ~ 0,
           is.na(parcel_size) ~ NA_real_,
           TRUE ~ as.numeric(parcel_size)
         ))

# Make a list of PIDs that are still for sale
still_forsale <- listings_model %>%
  arrange(datetime) %>%
  group_by(pid) %>%
  filter(tail(status, 1) == "For Sale") %>%
  pull(pid) %>% unique()

# Set up training and validation sets' ------------------------------------

# Train on "Sold" listings, test against "for sale" listings
if (train_on == "sold") {
  training_set <- listings_model %>%
    filter(status == "Sold")
  
  test_set <- listings_model %>%
    filter(status == "For Sale", pid %in% still_forsale) %>%
    distinct(mls_no, pid, .keep_all = TRUE)
  
  # Train against everything, test against everything
} else if (train_on == "everything") {
  test_set <- training_set <- listings_model
  
  # Train on some fraction, then test on the remaining
} else if (is.numeric(train_on) & between(train_on, 0.5, 1)) {
  training_set <- listings_model %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    sample_frac(size = train_on)
  
  test_set <- listings_model %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    anti_join(training_set)
  
} else {
  error("Don't know how to train like that!")
}

suppressWarnings({
  complex_form <- price ~ loc_bin*(sqft_dummy + style_bin) + bathrooms + is_condo:(log2(floor + 1) +  parcel_size)
  complex_model <- training_set %>%
    glm(complex_form, data = .)
})

dumb_model <- training_set %>%
  lm(price ~ loc_bin:sqft_tla, data = .)

test_set <- test_set %>%
  mutate(price = price,
         complex_prd = predict(complex_model, test_set, allow.new.levels = TRUE), # Prediction by complex model
         dumb_prd = predict(dumb_model, test_set),  # Prediction by simple model
         xsv = complex_prd - price, # Excess value
         xsv_pct = xsv / price, # Excess value %
         xsv_z = (xsv_pct - median(xsv_pct, na.rm = TRUE))/mad(xsv_pct, na.rm = TRUE)) # Non-parametric Z-score of excess value


complex_model_fig <- test_set %>%
  ggplot(aes(x = price, y = complex_prd)) +
  geom_point(aes(color = loc_bin), na.rm = TRUE, alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0, lty = 2) +
  scale_color_discrete(name = "", guide = FALSE) +
  scale_x_continuous(name = "Asking Price", labels = scales::dollar) +
  scale_y_continuous(name = "Predicted Sale Price", labels = scales::dollar) +
  ggtitle("Complex Model", 
          subtitle = paste0("R2 = ", round(cor(test_set$price, test_set$complex_prd)^2, 3)))

dumb_model_fig <- test_set %>%
  ggplot(aes(x = price, y = dumb_prd)) +
  geom_point(aes(color = loc_bin), na.rm = TRUE, alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0, lty = 2) +
  scale_color_discrete(name = "") +
  scale_x_continuous(name = "Asking Price", labels = scales::dollar) +
  scale_y_continuous(name = NULL, labels = NULL) +
  ggtitle("Dumb Model", 
          subtitle = paste0("R2 = ", round(cor(test_set$price, test_set$dumb_prd)^2, 3)))


model_figs <- complex_model_fig + dumb_model_fig
model_figs

# ggplot(data = complex_model$data, aes(x = price, y = resid(complex_model))) +
#   geom_point(alpha = 0.1) +
#   geom_smooth()


