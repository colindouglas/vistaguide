library(tidyverse)
library(tidytext)
library(patchwork)
source('pricing-model.R')

# There's absolutely no signal in here

feelings <- c("trust", "fear", "negative", "sadness", "anger", "surprise", 
              "positive", "disgust", "joy", "anticipation")[c(2:5, 8)]

test_sent <- filter(get_sentiments("nrc"), sentiment %in% feelings)


sentiment <- test_set %>%
  distinct(pid, .keep_all = TRUE) %>%
  select(pid, description) %>%
  filter(nchar(description) > 20) %>%
  unnest_tokens(word, description) %>%
  left_join(test_sent, by = "word") %>%
  group_by(pid) %>%
  summarize(words = n(),
            sentiment_abs = sum(!is.na(sentiment), na.rm = TRUE)) %>%
  mutate(sentiment_norm = (sentiment_abs/words - mean(sentiment_abs/words))/sd(sentiment_abs/words))

listings <- test_set %>% 
  left_join(sentiment, by = "pid")

abs_fig <- listings %>%
  ggplot(aes(x = price, y = words)) +
  geom_point() +
  geom_smooth(method = "lm", formula = y~x) +
  ggtitle("Absolute Sentiment") +
  ggtitle("Sentiment Density", subtitle = paste(feelings, collapse = ", "))

rel_fig <- listings %>%
  ggplot(aes(x = price, y = sentiment_norm)) +
  geom_point() +
  geom_smooth(method = "lm", formula = y~x) +
  ggtitle("Sentiment Density", subtitle = paste(feelings, collapse = ", "))

abs_fig + rel_fig