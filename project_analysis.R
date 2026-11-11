library(tidyverse)
library(jsonlite)
library(lubridate)
library(sf)
library(tigris)
library(scales)
library(viridis)

options(tigris_use_cache = TRUE)

business_file <- path.expand(
  "~/Downloads/Yelp JSON/yelp_dataset/yelp_academic_dataset_business.json"
)

review_file <- path.expand(
  "~/Downloads/Yelp JSON/yelp_dataset/yelp_academic_dataset_review.json"
)

file.exists(business_file)
file.exists(review_file)

business_raw <- jsonlite::stream_in(
  file(business_file),
  verbose = FALSE
)

business <- business_raw |>
  select(
    business_id,
    name,
    address,
    city,
    state,
    postal_code,
    latitude,
    longitude,
    stars,
    review_count,
    categories
  )

dim(business)
glimpse(business)

new_orleans_business <- business |>
  filter(city == "New Orleans", state == "LA")

dim(new_orleans_business)
head(new_orleans_business)

saveRDS(
  new_orleans_business,
  "new_orleans_business.rds"
)

new_orleans_restaurants <- business |>
  filter(
    state == "LA",
    city == "New Orleans",
    !is.na(categories),
    str_detect(
      categories,
      regex("Restaurants", ignore_case = TRUE)
    )
  ) |>
  mutate(
    postal_code = na_if(postal_code, ""),
    categories = str_squish(categories),
    business_name = str_squish(name)
  ) |>
  distinct(business_id, .keep_all = TRUE)

new_orleans_restaurants |>
  summarise(
    number_of_restaurants = n(),
    missing_latitude = sum(is.na(latitude)),
    missing_longitude = sum(is.na(longitude)),
    missing_categories = sum(is.na(categories))
  )

View(business)
View(new_orleans_restaurants)

category_counts <- new_orleans_restaurants |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_squish(categories)) |>
  filter(category != "Restaurants") |>
  count(category, sort = TRUE)

View(category_counts)

selected_restaurants <- new_orleans_restaurants |>
  filter(
    str_detect(
      categories,
      regex(
        "Cajun/Creole|Southern|American \\(New\\)|American \\(Traditional\\)",
        ignore_case = TRUE
      )
    )
  )

dim(selected_restaurants)
View(selected_restaurants)

best_restaurants <- selected_restaurants |>
  filter(review_count >= 50) |>
  arrange(desc(stars), desc(review_count))

View(best_restaurants)

overall_mean <- mean(
  selected_restaurants$stars,
  na.rm = TRUE
)

prior_reviews <- 100

best_restaurants_adjusted <- best_restaurants |>
  mutate(
    adjusted_rating =
      (review_count / (review_count + prior_reviews)) * stars +
      (prior_reviews / (review_count + prior_reviews)) * overall_mean
  ) |>
  arrange(
    desc(adjusted_rating),
    desc(review_count)
  )

View(best_restaurants_adjusted)

restaurant_ids <- selected_restaurants |>
  select(business_id)

review_chunks <- list()

review_handler <- function(chunk) {
  keep <- chunk |>
    select(
      review_id,
      user_id,
      business_id,
      stars,
      date,
      text,
      useful,
      funny,
      cool
    ) |>
    semi_join(
      restaurant_ids,
      by = "business_id"
    )
  
  if (nrow(keep) > 0) {
    review_chunks[[length(review_chunks) + 1L]] <<- keep
  }
}

jsonlite::stream_in(
  file(review_file),
  handler = review_handler,
  pagesize = 500,
  verbose = FALSE
)

selected_reviews <- bind_rows(review_chunks)

rm(review_chunks, review_handler, restaurant_ids)
gc()

dim(selected_reviews)

saveRDS(
  selected_reviews,
  "selected_reviews.rds"
)


review_summary <- selected_reviews |>
  group_by(business_id) |>
  summarise(
    review_mean = mean(stars, na.rm = TRUE),
    review_n = n(),
    .groups = "drop"
  )

restaurant_analysis <- selected_restaurants |>
  left_join(review_summary, by = "business_id")

area_summary <- restaurant_analysis |>
  group_by(postal_code) |>
  summarise(
    restaurants = n(),
    average_rating = mean(stars, na.rm = TRUE),
    total_reviews = sum(review_count, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(average_rating), desc(total_reviews))

View(area_summary)

area_summary_reliable <- area_summary |>
  filter(
    !is.na(postal_code),
    restaurants >= 10
  ) |>
  arrange(
    desc(average_rating),
    desc(total_reviews)
  )

View(area_summary_reliable)
