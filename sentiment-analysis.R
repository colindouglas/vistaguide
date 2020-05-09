library(tidyverse)
library(tidytext)
library(patchwork)

listings <- read_csv("data/listings-clean.csv") %>%
  filter(price < 1000000, sqft_mla > 400,
         type %in% c("Single Family", "Condominium"),
         loc_bin != "Rest of Province")

test_sent <- get_sentiments("nrc")


# Count the number of sentimental words in each PID's description
sentiment <- listings %>%
  distinct(pid, .keep_all = TRUE) %>%
  select(pid, description) %>%
  filter(nchar(description) > 20) %>%
  unnest_tokens(word, description) %>%
  left_join(test_sent, by = "word") %>%
  group_by(pid, sentiment) %>%
  summarize(sent_words = n()) %>%
  mutate(sentiment = ifelse(is.na(sentiment), "filler", sentiment)) # Classify non-sentimental words as "filler"


# Merge on to listing data, normalize to description word count
listings <- listings %>%
  mutate(words = str_count(description, "\\S+")) %>%
  distinct(pid, price, words, .keep_all = TRUE) %>%
  select(pid, price, words) %>%
  inner_join(sentiment, by = "pid") %>%
  mutate(sent_norm = sent_words/words)

# # Test plot
# listings %>%
#   ggplot(aes(x = price, y = sent_norm)) +
#   geom_point(aes(color = sentiment)) +
#   geom_smooth(method = "lm", formula = y~x, aes(color = sentiment)) 


# Make it wide-ways to make it easier to fit a model
listing_wide <- listings %>%
  pivot_wider(id_cols = c("pid", "price", "words"), names_from = sentiment, values_from = sent_norm, values_fill = list(sent_norm = 0)) 

# Fit the actual model
sent_model <- listing_wide %>% 
  lm(data = ., formula = price ~ words + positive + negative + filler + joy +  sadness + anger) 

# summary(sent_model)

# Use the model to fit prices to each listing. price_sent_z is the guessed price, normalized (mean = 0)
listing_predictions <- listing_wide %>%
  mutate(price_sent = predict(sent_model)) %>%
  mutate(price_sent_z = (price_sent - mean(price_sent))/sd(price_sent))

desc_scores <- listing_predictions %>%
  select(pid, desc_score = price_sent)
