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
