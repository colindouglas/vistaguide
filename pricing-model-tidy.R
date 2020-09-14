library(tidyverse)
library(tidymodels)
library(patchwork)
source("setup-constants.R")
source("connect-db.R")

# Get data from db --------------------------------------------------------

properties <- tbl(dbcon, "properties")
updates <- tbl(dbcon, "updates") 
geocode <- tbl(dbcon, "geocode")

sales <- updates %>%
  left_join(properties, by = "prop_id") %>%
  left_join(geocode, by = "address") %>%
  filter(loc_bin != "Rest of Province", 
         !is.na(price), price < 1e6,
         !(is.na(sqft_tla) & is.na(sqft_mla)),
         type %in% c("Single Family", "Condominium")) %>%
  collect() %>%
  select(-x, -y) %>%
  distinct(pid, status, price, .keep_all = TRUE) 

# Data cleanup ------------------------------------------------------------

# If one of the sqft numbers is NA, use the other
# If they're both present, use the mean
sales <- sales %>%
  mutate(sqft = case_when(
    is.na(sqft_tla) ~ as.numeric(sqft_mla),
    is.na(sqft_mla) ~ as.numeric(sqft_tla),
    TRUE ~ (sqft_mla + sqft_tla) / 2),
  per_sqft = price / sqft)

# If the location is on the peninsula, make the location bin more specific
sales <- sales %>%
  mutate(loc_bin = factor(ifelse(
      loc_bin == "Halifax Peninsula", 
      peninsula_codes[postal_first], 
      loc_bin)))


sold <- filter(sales, status == "Sold")  # Training
for_sale <- filter(sales, 
                   status == "For Sale",
                   !(pid %in% sold$pid))  # Application

# Fit KNN to find out price per sqft in neighborhood ----------------------

set.seed(42069)

# Define the treatment of each variable
sales_recipe_knn <- sold %>%
  recipe(per_sqft ~ lon + lat + update_id) %>%
  update_role(update_id, new_role = "ID") %>%
  step_naomit(lat, lon, per_sqft) %>%
  prep()

# Extract the training set
sales_training <- juice(sales_recipe_knn)


# Implement KNN price/sqft model ------------------------------------------

# From tuning, the best k for KNN is approximately 3% of the training set
k_best <- floor(nrow(sold) * 0.03)

# Implement the model 
sales_knn <- nearest_neighbor(neighbors = k_best, weight_func = "inv") %>%
  set_engine("kknn") %>%
  set_mode("regression")

sales_prepped <- bake(sales_recipe_knn, sold)

# Use it to predict the price/sqft of the points with lat/lon data
sales_knn_fit <- sales_knn %>%
  fit(per_sqft ~ lat + lon, data = sales_prepped) 

sales_pred <- sales_knn_fit %>%
  predict(sold) %>%
  rename(pred_per_sqft_knn = .pred) %>%
  add_column(update_id = sales_prepped$update_id)

sold <- left_join(sold, sales_pred, by = "update_id")

# For the points where we're missing lat/lon data, try to figure out
# the price/sqft based on first the average price in the postal code FSA and
# then, if that's missing, the average price in the loc_bin

# Figure out the approximate price per sqft based on the postal_first (FSA) in the training set
pred_per_sqft_postal <- sold %>%
  group_by(postal_first) %>%
  summarize(pred_per_sqft_postal = mean(price / sqft), .groups = "drop")

pred_per_sqft_locbin <- sold %>%
  group_by(loc_bin) %>%
  summarize(pred_per_sqft_locbin = mean(price / sqft), .groups = "drop")

# If there's not lat/lon data, use loc_bin averages for the persqft value

sales_persqft <- sold %>%
  left_join(pred_per_sqft_postal, by = "postal_first") %>%
  left_join(pred_per_sqft_locbin, by = "loc_bin") %>%
  mutate(pred_per_sqft = coalesce(pred_per_sqft_knn, pred_per_sqft_postal, pred_per_sqft_locbin)) %>%
  select(update_id, pred_per_sqft)


# Now use the KNN per_sqft to fit a linear model --------------------------

# Define the treatment of each variable
sales_recipe_lm <- sold %>%
  left_join(sales_persqft, by = "update_id") %>%
  recipe(price ~ pred_per_sqft + sqft + update_id + garage + style + bathrooms + building_age + waterfront) %>%
  update_role(update_id, new_role = "ID") %>%
  step_mutate(building_age = ifelse(is.na(building_age), mean(building_age, na.rm = TRUE), building_age),
              waterfront_access = ifelse(grepl("Access:", waterfront), TRUE, FALSE)) %>%
  prep()

# Apply the treatment to the testing set
sold_training <- bake(sales_recipe_lm, left_join(sold, sales_persqft, by = "update_id")) 

sales_lm_fit <- linear_reg(mode = "regression") %>%
  set_engine("lm") %>%
  fit(price ~ pred_per_sqft:sqft:style + garage + bathrooms + building_age + waterfront_access, data = sold_training) 


# Apply both models to the application set --------------------------------

# Predict the price/sqft for the general area for properties with lat/lon data
for_sale_pred_persqft <- for_sale %>%
  bake(sales_recipe_knn, .) %>%
  predict(sales_knn_fit, .) %>%
  bind_cols(bake(sales_recipe_knn, for_sale), .) %>%
  select(update_id, pred_per_sqft_knn = .pred)

# Join the price/sqft for properties with lat/lon data
for_sale <- left_join(for_sale, for_sale_pred_persqft, by = "update_id")

# If there is no lat/lon data, use the mean for the FSA, and then if that's missing using the mean for the location bin
for_sale_persqft <- for_sale %>%
  left_join(pred_per_sqft_postal, by = "postal_first") %>%
  left_join(pred_per_sqft_locbin, by = "loc_bin") %>%
  mutate(pred_per_sqft = coalesce(pred_per_sqft_knn, pred_per_sqft_postal, pred_per_sqft_locbin)) %>%
  select(update_id, pred_per_sqft)

# For the price/sqft data onto the dataframe for future fitting
for_sale <- left_join(for_sale, for_sale_persqft, by = "update_id")

# Prep the data and apply the linear model to the dataset to figure out the remaining bits
for_sale_pred <- bake(sales_recipe_lm, for_sale) %>%
  predict(sales_lm_fit, .) %>%
  bind_cols(for_sale, .) %>%
  rename(pred_price = .pred) %>%
  filter(pred_price < 1.5e6)


# Calculate simple metrics for determining value
for_sale_pred <- for_sale_pred %>%
  mutate(xsv = pred_price - price, # Excess value
         xsv_pct = xsv / price, # Excess value %
         xsv_z = (xsv_pct - median(xsv_pct, na.rm = TRUE))/mad(xsv_pct, na.rm = TRUE)) # Non-parametric Z-score of excess value

             