## Build base punt data, ordered for lead()/lag()
pbp_ordered <- pbp %>%
  arrange(game_id, play_id) %>%
  group_by(game_id) %>%
  mutate(
    next_play_type = lead(play_type),
    next_posteam = lead(posteam),
    next_yardline_100 = lead(yardline_100),
    next_game_half = lead(game_half),
  ) %>%
  ungroup()

punt_model_data <- pbp_ordered %>%
  filter(play_type == "punt") %>%
  mutate(
    valid_next_play = !is.na(next_yardline_100) & game_half == next_game_half,
    net_value = next_yardline_100 - yardline_100,  #target formula
    punting_team_kept_ball = next_posteam == posteam,
  ) %>%
  filter(valid_next_play)


## Handle rare edge-cases
# Blocked/muffed punts recovered by the punting team break the standard
# field-position formula (possession doesn't change hands). Safeties are
# scoring events, excluded and handled downstream in the win-probability engine.
# See docs/methodology.md for full derivation of the placeholder values below.

punt_model_data <- punt_model_data %>%
  filter(!str_detect(desc, "SAFETY")) %>%
  mutate(
    net_value_final = case_when(
      punting_team_kept_ball ~ 20,
      TRUE ~ net_value
    )
  )


## Derive leakage-safe punter/returner hsitory from net_value_final
punter_stats <- punt_model_data %>%
  arrange(punter_player_id, game_date, game_id, play_id) %>%
  group_by(punter_player_id) %>%
  mutate(
    punter_career_gross_avg = dplyr::lag(cummean(kick_distance)),
    punter_career_net_avg = dplyr::lag(cummean(net_value_final))
  ) %>%
  ungroup() %>%
  select(game_id, play_id, punter_player_id, punter_career_gross_avg, punter_career_net_avg)


returner_stats <- punt_model_data %>%
  filter(play_type == "punt", !is.na(punt_returner_player_id), !is.na(return_yards)) %>%
  arrange(punt_returner_player_id, game_date, game_id, play_id) %>%
  group_by(punt_returner_player_id) %>%
  
  #flip the sign of net_value_final (higher value = better for returner's team)
  mutate(returner_career_impact = dplyr::lag(cummean(-net_value_final))) %>%
           ungroup() %>%
           select(game_id, play_id, punt_returner_player_id, returner_career_impact)


## Rejoin features, parse all weather conditions, and remove na values from the data 
punt_model_data <- punt_model_data %>%
  mutate(
    # Parse weather conditions (just like field goal model)
    surface = str_trim(tolower(surface)),
    surface = ifelse(is.na(surface) | surface == "", "unknown", surface),
    surface = ifelse(surface == "unknown", "grass", surface),  # fold into most common category
    surface = factor(surface, levels = unique(surface)),

    weather_clean = tolower(weather),
    weather_cat = case_when(
      str_detect(weather_clean, "indoor|indoors|controlled climate") ~ "indoor",
      str_detect(weather_clean, "snow|sleet|blizzard|snow showers") ~ "snow",
      str_detect(weather_clean, "rain|storm|shower|drizzle") ~ "rain",
      str_detect(weather_clean, "fog|mist|haze") ~ "fog",
      str_detect(weather_clean, "cloud|overcast|fair") ~ "cloudy",
      str_detect(weather_clean, "clear|sunny|sun") ~ "clear",
      str_detect(weather_clean, "^temp|^\\s*temp") ~ "other",
      TRUE ~ "other"
    ),

    # Indoor varaible
    indoor = if_else(roof %in% c("closed", "dome"), 1, 0)
  ) %>%
  select(-weather_clean) %>%

  # Remove any na values from predictors
  filter(
    !is.na(kick_distance),
    !is.na(yardline_100),
    !is.na(game_seconds_remaining),
    !is.na(score_differential),
    !is.na(weather_cat),
    !is.na(indoor),
    !is.na(surface)
  ) %>%
  mutate(
    weather = na_if(weather, "")
  ) %>%
  
  # Left join the punter and returner stats to punter_model_data
  left_join(punter_stats, by = c("game_id", "play_id", "punter_player_id"))%>%
  left_join(returner_stats, by = c("game_id", "play_id", "punt_returner_player_id")) %>%
  
  # Imput a placeholder value of 0 for returners that don't have their id recorded
  mutate(
    no_returner = is.na(returner_career_impact),
    returner_career_impact = ifelse(is.na(returner_career_impact), 0, returner_career_impact)
  ) %>%
  
  # Remove rows with no punter history (first tracked punt for that punter, ~95 rows).
  filter(!is.na(punter_career_gross_avg), !is.na(punter_career_net_avg))

# Finalize the feature list for the model formula
punt_model_data <- punt_model_data %>%
  select(season, yardline_100, weather_cat, indoor, surface, punter_career_gross_avg, punter_career_net_avg, returner_career_impact, net_value_final, no_returner)

# Train/test split
punt_train_data <- punt_model_data %>%
  filter(season <= 2021)
punt_test_data <- punt_model_data %>%
  filter(season > 2021)


## Build Models
# Linear Regression Model
punt_lm_model <- lm(net_value_final ~ 
                      yardline_100 
                    + weather_cat 
                    + indoor 
                    + surface 
                    + punter_career_gross_avg 
                    + punter_career_net_avg 
                    + returner_career_impact 
                    + no_returner 
                    + yardline_100:punter_career_net_avg,
                    data = punt_train_data)

# GAM model
punt_gam_model <- gam(net_value_final ~ 
                        s(yardline_100) 
                      + weather_cat 
                      + indoor 
                      + surface 
                      + s(punter_career_gross_avg) 
                      + s(punter_career_net_avg) 
                      + s(returner_career_impact) 
                      + no_returner 
                      + ti(yardline_100, punter_career_net_avg),
  data = punt_train_data,
  family = gaussian()
)


## Compare the models
# Generate predictions on the holdout set
punt_lm_preds <- predict(punt_lm_model, newdata = punt_test_data)
punt_gam_preds <- predict(punt_gam_model, newdata = punt_test_data)

# Define metric functions
rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2))
mae  <- function(actual, predicted) mean(abs(actual - predicted))

# Compare
rmse_lm  <- rmse(punt_test_data$net_value_final, punt_lm_preds)
rmse_gam <- rmse(punt_test_data$net_value_final, punt_gam_preds)
mae_lm   <- mae(punt_test_data$net_value_final, punt_lm_preds)
mae_gam  <- mae(punt_test_data$net_value_final, punt_gam_preds)

rmse_lm # ~10.49
rmse_gam # ~10.26
mae_lm # ~7.21
mae_gam # ~6.94

#Since the GAM has smaller values for both RMSE and MAE values, it is the 
#better model to interpret. MAE of ~6.94  yards means, on average, the GAM's 
#prediction for net field-position valuie is off by about 7 yards from what 
#actually happened. That's reasonable because field position swings with other 
#factors that a model can't predict (bounces, missed tackles, etc.), so an 
#average miss of under a touchdown drive's worth of yardage is a solid result, 
#not something to be concerned about.  
