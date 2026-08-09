## Gather more information about the individual kicker's ability for the team

# Primarily, we are gathering kicker fg% for season, career, and career long
kicker_stats <- fourth %>%
  
  # kicker_career_fg_pct
  filter(play_type == "field_goal") %>%
  arrange(kicker_player_id, game_date, game_id, play_id) %>%
  group_by(kicker_player_id) %>%
  mutate(
    made_flag = as.integer(field_goal_result == "made"),
    cum_made = cumsum(field_goal_result == "made"),
    cum_att  = row_number(),
    kicker_career_fg_pct = (cum_made - made_flag) / (cum_att - 1),
    made_dist = ifelse(made_flag == 1, kick_distance, NA_real_),
    kicker_long_made = dplyr::lag(cummax(replace(made_dist, is.na(made_dist), -Inf)))
  ) %>%
  ungroup() %>%
  
  # kicker_season_fg_pct
  group_by(kicker_player_id, season) %>%
  mutate(
    season_made = cumsum(made_flag),
    season_att  = row_number(),
    kicker_season_fg_pct = (season_made - made_flag) / (season_att - 1)
  ) %>%
  ungroup() %>%
  
  # kicker_long_made
  group_by(kicker_player_id) %>%
  mutate(kicker_long_made = ifelse(is.finite(kicker_long_made), kicker_long_made, NA)) %>%
  ungroup() %>%
  
  # Fix -inf for kickers with no made fg's
  mutate(
    kicker_long_made = ifelse(is.finite(kicker_long_made),
                              kicker_long_made,
                              NA)) %>%
  # Keep columns needed only for joining
  select(game_id, play_id, kicker_player_id, kicker_season_fg_pct, kicker_career_fg_pct, kicker_long_made)


## Filter data for field goals 
fg_model_data <- fourth %>%
  filter(play_type == "field_goal",
         extra_point_attempt == 0) %>%
  
  # Variables needed for models
  select(
    game_id, play_id,
    kick_distance, yardline_100, goal_to_go, ydstogo,
    qtr, half_seconds_remaining, game_seconds_remaining,
    score_differential,
    posteam_timeouts_remaining, defteam_timeouts_remaining,
    posteam_type,
    season_type,
    stadium, roof, surface, weather,
    side_of_field,
    kicker_player_id, kicker_player_name, field_goal_result, season
  ) %>%
  
  # Create outcome variable (fg_made)
  mutate(fg_made = ifelse(field_goal_result == "made", 1, 0)) %>%
  
  # Join kicker stats
  left_join(kicker_stats, by = c("game_id", "play_id", "kicker_player_id"))

# Parse weather conditions
fg_model_data <- fg_model_data %>%
  mutate(
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
    # Indoor varaible good for model
    indoor = if_else(roof %in% c("closed", "dome"), 1, 0)
  ) %>%
  select(-weather_clean) %>%
  # Remove any na values from predictors
  filter(
    !is.na(kick_distance),
    !is.na(yardline_100),
    !is.na(game_seconds_remaining),
    !is.na(score_differential),
    !is.na(kicker_season_fg_pct),
    !is.na(kicker_career_fg_pct),
    !is.na(kicker_long_made),
    !is.na(weather_cat),
    !is.na(indoor),
    !is.na(surface)
  ) %>%
  mutate(
    surface = na_if(surface, ""),
    weather = na_if(weather, "")
  )

# train/test split for models
kick_train_data <- fg_model_data %>%
  filter(season <= 2021)
kick_test_data <- fg_model_data %>%
  filter(season > 2021)

## Build Models
# Logistic Regression Model
fg_log_model <- glm(
  fg_made ~ 
    # base variables
    kick_distance +
    yardline_100 +
    qtr +
    game_seconds_remaining +
    score_differential +
    kicker_season_fg_pct +
    kicker_career_fg_pct +
    kicker_long_made +
    weather_cat +
    indoor +
    surface +
    
    # Interactions
    kick_distance:weather_cat +
    kick_distance:indoor +
    kick_distance:surface +
    kick_distance:kicker_season_fg_pct +
    kick_distance:kicker_career_fg_pct +
    kick_distance:score_differential +
    kick_distance:game_seconds_remaining,
  
  data = kick_train_data,
  family = binomial(link = "logit")
)

# Generalized Additive Model (GAM)
fg_gam_model <- gam(
  fg_made ~ 
    # numeric smooths
    s(kick_distance) +
    s(yardline_100) +
    s(game_seconds_remaining) +
    s(score_differential) +
    
    # linear numeric predictors
    kicker_season_fg_pct +
    kicker_career_fg_pct +
    kicker_long_made +
    
    # categorical predictors (must stay linear)
    weather_cat +
    indoor +
    surface +
    
    # nonlinear numeric × numeric interactions
    ti(kick_distance, kicker_season_fg_pct) +
    ti(kick_distance, kicker_career_fg_pct) +
    ti(kick_distance, score_differential) +
    ti(kick_distance, game_seconds_remaining),
  
  data = kick_train_data,
  family = binomial(link = "logit")
)

# Compare the Models
#Generate Prediction Probabilities for each Model
fg_log_preds <- predict(fg_log_model, newdata = kick_test_data, type = "response")
fg_gam_preds <- predict(fg_gam_model, newdata = kick_test_data,  type = "response")

#Add varaibles to dataset
kick_test_data <- kick_test_data %>%
  mutate(
    log_pred = fg_log_preds,
    gam_pred = fg_gam_preds
  ) %>%
  filter(!is.na(log_pred), !is.na(gam_pred))

#Compare AUC
fg_auc_log <- roc(kick_test_data$fg_made, kick_test_data$log_pred)$auc
fg_auc_gam <- roc(kick_test_data$fg_made, kick_test_data$gam_pred)$auc
fg_auc_log
fg_auc_gam

#Compare Log-Loss (Probability Accuracy)
fg_log_loss <- function(actual, predicted) {
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}
fg_ll_log <- log_loss(kick_test_data$fg_made, kick_test_data$log_pred)
fg_ll_gam <- log_loss(kick_test_data$fg_made, kick_test_data$gam_pred)
fg_ll_log
fg_ll_gam

#Calibration Curves (Probability Realism)

# Logistic Model Calibration
fg_cal_log <- kick_test_data %>%
  mutate(bin = ntile(log_pred, 10)) %>%
  group_by(bin) %>%
  summarize(
    mean_pred = mean(log_pred),
    mean_actual = mean(fg_made)
  )

fg_cal_gam <- kick_test_data %>%
  mutate(bin = ntile(gam_pred, 10)) %>%
  group_by(bin) %>%
  summarize(
    mean_pred = mean(gam_pred),
    mean_actual = mean(fg_made)
  )

fg_brier_score_log <- mean((kick_test_data$fg_made - kick_test_data$log_pred)^2)
fg_brier_score_gam <- mean((kick_test_data$fg_made - kick_test_data$gam_pred)^2)
fg_brier_score_log
fg_brier_score_gam

# AUC (log = 0.7423, gam = 0.7448, gam is better) 
# Log-loss (log = 0.3643, gam = 0.3604, gam is better) 
# Calibration via Brier Score (log = 0.112, gam = 0.113, gam is better)

# Overall, the GAM model provided more accurate, better-calibrated, and more discriminative 
# predictions than the logistic regression model. While the improvements were small, they were 
# consistent across all evaluation metrics, showing the value of allowing nonlinear relationships 
# in field-goal modeling.
