# This script loads lat/long data, filters it for properties on the peninsula, and then fits
# a 2D price/sqft surface over it

library(ggmap)
library(tidyverse)
register_google(key = filter(read_csv("../secrets.csv", col_types = cols()), website == "gmaps")$key)

center <- c(lat = 44.65, lon = -63.60)
widths <- c(lat = 0.2, lon = -0.2)

lon_ends <- center["lon"] + c(1, -1) * widths["lon"]
lon_start <- min(lon_ends)
lon_stop <- max(lon_ends)

lat_ends <- center["lat"] + c(1, -1) * widths["lat"]
lat_start <- min(lat_ends)
lat_stop <- max(lat_ends)

zoom_level <- 13
raster_width <- 0.002

listings <- read_csv("data/listings-clean.csv", col_types = cols()) %>%
  mutate(per_sqft = price/sqft_tla) %>%
  filter(between(lon, lon_start, lon_stop),
         between(lat, lat_start, lat_stop),
         per_sqft < 1000)

halifax <- get_googlemap(center = paste(center, collapse = ", "), zoom = zoom_level)

fit <- listings %>%
  filter(!is.na(per_sqft)) %>%
  loess(per_sqft ~ lon + lat, data = ., span = 0.1)

prediction <- tibble(
  crossing(lon = seq(lon_start, lon_stop, by = raster_width),
           lat = seq(lat_start, lat_stop, by = raster_width))
)


prediction <- prediction %>%
  mutate(per_sqft = predict(fit, prediction),
         per_sqft = ifelse((per_sqft < 100 | per_sqft > 750), NA, per_sqft))


# Find where the fitting failed and exclude them from the second pass of loess fitting
prediction_no_fits <- prediction %>%
  filter(is.na(per_sqft))

prediction <- tibble(
  crossing(lon = seq(lon_start, lon_stop, by = raster_width),
           lat = seq(lat_start, lat_stop, by = raster_width)) %>%
    anti_join(prediction_no_fits, by = c("lat", "lon"))
)

prediction <- prediction %>%
  mutate(per_sqft = predict(fit, prediction),
         per_sqft = ifelse((per_sqft < 100 | per_sqft > 750), NA, per_sqft))

hfx_heatmap <- halifax %>%
  ggmap() +
  geom_point(data = listings, aes(x = lon, y = lat), alpha = 0.2, na.rm = TRUE) +
  geom_contour_filled(data = prediction, 
                      aes(x = lon, y = lat, z = per_sqft), 
                      alpha = 0.5, na.rm = TRUE, binwidth = 50) +
  labs(fill = "$/Sq. Ft") +
  theme(axis.title.x = element_blank(),
        axis.text.x  = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title.y = element_blank(),
        axis.text.y  = element_blank(),
        axis.ticks.y = element_blank())
