# This script loads lat/long data, filters it for properties on the peninsula, and then fits
# a 2D price/sqft surface over it

library(ggmap)

register_google(key = filter(read_csv("../oauth_keys.csv", col_types = cols()), website == "gmaps")$key)

lon_start <- -63.625
lon_stop <- -63.525

lat_start <- 44.61
lat_stop <- 44.68

listings <- read_csv("data/listings-clean.csv", col_types = cols()) %>%
  mutate(per_sqft = price/sqft_tla) %>%
  filter(between(lon, lon_start, lon_stop),
         between(lat, lat_start, lat_stop),
         per_sqft < 1000)

halifax <- get_googlemap(center = "Halifax, NS, Canada", zoom = 13)

fit <- listings %>%
  filter(!is.na(per_sqft)) %>%
  loess(per_sqft ~ lon + lat, data = ., span = 0.1)

prediction <- tibble(
  crossing(lon = seq(lon_start, lon_stop, by = 0.01),
           lat = seq(lat_start, lat_stop, by = 0.01))
)


prediction$per_sqft <- predict(fit, prediction)


halifax %>%
  ggmap() +
  geom_point(data = listings, aes(x = lon, y = lat), alpha = 0.2) +
  geom_tile(data = prediction, aes(x = lon, y = lat, fill = per_sqft), alpha = 0.5) +
  scale_fill_gradientn(colours = terrain.colors(10))
