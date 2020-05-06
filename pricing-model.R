library(tidyverse)
library(tidymodels)
library(patchwork)
source("setup.R")

mlaw <- 0.5  # Weighting for MLA sqft number
train_on_sold <- TRUE  # Train on "Sold", test on "For Sale"?

listings <- read_csv("data/listings-clean.csv") %>%
  distinct(pid, status, .keep_all = TRUE) %>%
  filter(price < 1000000, sqft_mla > 400,
         type %in% c("Single Family", "Condominium"),
         loc_bin != "Rest of Province") %>%
  rowwise() %>%
  mutate(sqft_dummy = max(0, (sqft_mla*mlaw + sqft_tla*(1-mlaw) - 750)),
         is_peninsula = loc_bin == "Halifax Peninsula",
         condo_fee_sqft = ifelse(is.na(condo_fee), 0, condo_fee/sqft_mla),
         assessment_in_thousands = ifelse(is.na(assessment), 0, assessment/1000)) %>%
  ungroup() %>%
  mutate(building_age = ifelse(is.na(building_age), mean(building_age, na.rm = TRUE), building_age))


# Set up training and validation sets' ------------------------------------
if (train_on_sold) {
  
  training_set <- listings %>%
    filter(status == "Sold")
  
  test_set <- listings %>%
    filter(status == "For Sale") %>%
    distinct(address, .keep_all = TRUE)
  
} else {
  
  training_set <- listings %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    sample_frac(size = 0.75)
  
  test_set <- listings %>%
    filter(status %in% c("For Sale", "Sold")) %>%
    anti_join(training_set)
  
}


complex_form <- price ~ loc_bin:(sqft_dummy + style ) + building_age + days_on_market + assessment_in_thousands

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


