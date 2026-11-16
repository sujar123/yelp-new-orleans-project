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

exists("new_orleans_restaurants")
exists("selected_restaurants")
exists("business")


library(tidyverse)
library(sf)
library(tigris)

options(tigris_use_cache = TRUE)

new_orleans_business <- readRDS(
  "new_orleans_business.rds"
)

new_orleans_restaurants <- new_orleans_business |>
  filter(
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

dim(new_orleans_restaurants)
dim(selected_restaurants)

louisiana_places <- tigris::places(
  state = "LA",
  cb = TRUE,
  year = 2024,
  class = "sf"
)

restaurant_points <- selected_restaurants |>
  filter(
    !is.na(longitude),
    !is.na(latitude)
  ) |>
  st_as_sf(
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  )

restaurants_with_place <- restaurant_points |>
  st_join(
    louisiana_places |>
      st_transform(st_crs(restaurant_points)) |>
      select(
        GEOID,
        place_name = NAME
      ),
    join = st_within,
    left = TRUE
  )

restaurants_with_place |>
  st_drop_geometry() |>
  count(
    city,
    place_name,
    sort = TRUE
  )

orleans_tracts <- tigris::tracts(
  state = "LA",
  county = "Orleans",
  cb = TRUE,
  year = 2024,
  class = "sf"
)

restaurant_points_new_orleans <- restaurants_with_place |>
  filter(place_name == "New Orleans")

restaurants_with_tract <- restaurant_points_new_orleans |>
  st_join(
    orleans_tracts |>
      st_transform(st_crs(restaurant_points_new_orleans)) |>
      select(
        tract_id = GEOID,
        tract_name = NAME
      ),
    join = st_within,
    left = TRUE
  )

tract_summary <- restaurants_with_tract |>
  st_drop_geometry() |>
  group_by(tract_id, tract_name) |>
  summarise(
    restaurants = n(),
    average_rating = mean(stars, na.rm = TRUE),
    total_reviews = sum(review_count, na.rm = TRUE),
    .groups = "drop"
  ) |>
  filter(restaurants >= 5) |>
  arrange(desc(average_rating), desc(total_reviews))

View(tract_summary)



selected_reviews <- readRDS("selected_reviews.rds")

overall_review_mean <- mean(
  selected_reviews$stars,
  na.rm = TRUE
)

reviewer_baselines <- selected_reviews |>
  group_by(user_id) |>
  summarise(
    reviewer_mean = mean(stars, na.rm = TRUE),
    reviewer_reviews = n(),
    .groups = "drop"
  )

reviewer_adjusted_summary <- selected_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  mutate(
    adjusted_review_score =
      stars - reviewer_mean + overall_review_mean
  ) |>
  group_by(business_id) |>
  summarise(
    reviewer_adjusted_score = mean(
      adjusted_review_score,
      na.rm = TRUE
    ),
    review_rows = n(),
    unique_reviewers = n_distinct(user_id),
    .groups = "drop"
  )

View(reviewer_adjusted_summary)


restaurant_rankings <- selected_restaurants |>
  left_join(
    reviewer_adjusted_summary,
    by = "business_id"
  ) |>
  left_join(
    restaurants_with_tract |>
      st_drop_geometry() |>
      select(business_id, tract_id, tract_name),
    by = "business_id"
  ) |>
  filter(
    review_rows >= 20
  ) |>
  mutate(
    final_score =
      0.6 * reviewer_adjusted_score +
      0.4 * stars
  ) |>
  arrange(
    desc(final_score),
    desc(review_count)
  )

top_10_restaurants <- restaurant_rankings |>
  slice_head(n = 10) |>
  select(
    business_name,
    stars,
    review_count,
    reviewer_adjusted_score,
    final_score,
    tract_id,
    tract_name,
    latitude,
    longitude,
    categories
  )

View(
  selected_reviews |>
    slice_head(n = 100)
)

View(top_10_restaurants)


top10_points <- top_10_restaurants |>
  st_as_sf(
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  )

tract_map <- orleans_tracts |>
  st_transform(4326) |>
  ggplot() +
  geom_sf(
    fill = "gray95",
    color = "gray60"
  ) +
  geom_sf(
    data = top10_points,
    aes(color = final_score),
    size = 3
  ) +
  geom_sf_text(
    data = top10_points,
    aes(label = business_name),
    size = 2.5,
    check_overlap = TRUE
  ) +
  scale_color_viridis_c(
    name = "Final score"
  ) +
  labs(
    title = "Top 10 Selected Restaurants in New Orleans",
    subtitle = "Cajun/Creole, Southern, and American restaurants",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal()

tract_map


ggsave(
  "top10_restaurants_map.png",
  tract_map,
  width = 10,
  height = 7,
  dpi = 300
)

top_10_restaurants |>
  select(business_name, tract_name, final_score)

needed_objects <- c(
  "selected_restaurants",
  "selected_reviews",
  "reviewer_adjusted_summary",
  "restaurant_rankings",
  "top_10_restaurants",
  "category_counts",
  "area_summary_reliable",
  "tract_summary",
  "tract_map"
)

setNames(
  sapply(needed_objects, exists),
  needed_objects
)

category_counts <- selected_restaurants |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_squish(categories)) |>
  filter(category != "Restaurants") |>
  count(category, sort = TRUE)

View(category_counts)


category_plot_data <- category_counts |>
  slice_head(n = 12) |>
  mutate(category = fct_reorder(category, n))

category_plot <- ggplot(
  category_plot_data,
  aes(x = category, y = n)
) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(
    title = "Most Common Restaurant Categories",
    subtitle = "Among selected New Orleans restaurants",
    x = NULL,
    y = "Number of restaurants"
  ) +
  theme_minimal()

category_plot

View(selected_restaurants)


restaurant_categories <- selected_restaurants |>
  select(business_id, categories) |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_squish(categories)) |>
  select(business_id, category) |>
  distinct()

selected_categories <- c(
  "Cajun/Creole",
  "Southern",
  "American (New)",
  "American (Traditional)"
)

category_pairs <- restaurant_categories |>
  filter(category %in% selected_categories) |>
  inner_join(
    restaurant_categories |>
      filter(category %in% selected_categories),
    by = "business_id",
    suffix = c("_1", "_2")
  ) |>
  filter(category_1 < category_2) |>
  count(
    category_1,
    category_2,
    name = "restaurants_together",
    sort = TRUE
  )

View(category_pairs)


tract_summary |>
  filter(!is.na(tract_id), restaurants >= 10) |>
  summarise(
    geographic_areas = n(),
    total_restaurants = sum(restaurants)
  )


top10_plot <- top_10_restaurants |>
  mutate(
    business_name = forcats::fct_reorder(business_name, final_score)
  ) |>
  ggplot(aes(x = final_score, y = business_name)) +
  geom_col(fill = "steelblue") +
  labs(
    title = "Top 10 Restaurants in New Orleans",
    x = "Final Score",
    y = NULL
  ) +
  theme_minimal()

top10_plot

ggsave(
  "top10_restaurants_plot.png",
  top10_plot,
  width = 10,
  height = 7,
  dpi = 300
)


write_csv(top_10_restaurants, "top_10_restaurants.csv")
write_csv(category_counts, "category_counts.csv")
write_csv(category_pairs, "category_pairs.csv")
write_csv(tract_summary, "tract_summary.csv")

ggsave(
  "category_plot.png",
  category_plot,
  width = 10,
  height = 7,
  dpi = 300
)


geography_comparison <- bind_rows(
  restaurants_with_place |>
    st_drop_geometry() |>
    summarise(
      geographic_system = "Official place boundaries",
      areas = n_distinct(place_name, na.rm = TRUE),
      restaurants = n(),
      unmatched = sum(is.na(place_name))
    ),
  
  restaurants_with_tract |>
    st_drop_geometry() |>
    summarise(
      geographic_system = "Census tracts",
      areas = n_distinct(tract_id, na.rm = TRUE),
      restaurants = n(),
      unmatched = sum(is.na(tract_id))
    )
)

View(geography_comparison)

write_csv(
  geography_comparison,
  "geography_comparison.csv"
)
