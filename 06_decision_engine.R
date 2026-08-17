# flip posession outcome
flip_possession <- function(yardline_100, score_differential, timeouts_off, timeouts_def){
  list(
    yardline_100 = 100 - yardline_100,
    score_differential = - score_differential,
    posteam_timeouts_remaining = timeouts_def,
    defteam_timeouts_remaining = timeouts_off 
  )
}
#-----------------------------------------------------------------------------------------------------
## Outcome-state Buildiers
#-----------------------------------------------------------------------------------------------------
# 1. Go for it, succeed (results in 1st and 10 or goal-to-go, same team keeps ball)
state_convert_success <- function(yardline_100, ydstogo, score_differential, timeouts_off, timeouts_def, game_seconds_remaining){
  new_yardline <- yardline_100 - ydstogo
  
  if (new_yardline <= 0){
    # +6 (assume try extra point), then kickoff
    flipped <- flip_possession(75, score_differential + 7, timeouts_off, timeouts_def)
    return(c(list(down = 1, 
                  ydstogo = 10, 
                  game_seconds_remaining = max(game_seconds_remaining - 5, 0)), 
             flipped))
  }
  
  list(
    down = 1, 
    ydstogo = min(10, new_yardline),
    yardline_100 = new_yardline,
    score_differential = score_differential,
    posteam_timeouts_remaining = timeouts_off,
    defteam_timeouts_remaining = timeouts_def,
    game_seconds_remaining = max(game_seconds_remaining - 5, 0)
  )
}

# 2. Go for it,  fail (results in turnover on downs, possession flips at current spot)

  ##Compute expected yards gained on failed attempts
fail_yards_lookup <- fourth_go %>%
  filter(convert == 0, !is.na(yards_gained)) %>%
  mutate(ydstogo_bucket = case_when(
    ydstogo <= 2 ~ "short",
    ydstogo <= 5 ~ "medium",
    ydstogo <= 10 ~ "long",
    TRUE ~ "very_long"
  )) %>%
  group_by(ydstogo_bucket) %>%
  summarize(
    avg_yards_gained_on_fail = mean(yards_gained, na.rm = TRUE), 
    n = n()
  )
  ## Helper to look up right value given specific ydstogo
get_fail_yards <- function(ydstogo, failed_yards_lookup) {
  bucket <- case_when(
    ydstogo <= 2 ~ "short",
    ydstogo <= 5 ~ "medium",
    ydstogo <= 10 ~ "long",
    TRUE ~ "very_long"
  )
  failed_yards_lookup$avg_yards_gained_on_fail[failed_yards_lookup$ydstogo_bucket == bucket]
}

  ## Create actual function for failed conversion
state_convert_fail <- function(yardline_100, ydstogo, score_differential, timeouts_off, timeouts_def, game_seconds_remaining, failed_yards_lookup){
  expected_gain <- get_failed_yards(ydstogo, fail_lookup)
    # Ball is placed at the new spot (og yardline - gained)
  spot_after_fail <- max(yardline_100 - expected_gain, 1)
  flipped <- flip_possession(spot_after_fail, score_differential, timeouts_off, timeouts_def)
  c(list(down = 1, 
         ydstogo = 10, 
         game_seconds_remaining = max(game_seconds_remaining - 5, 0)), 
    
    flipped)
}


# 3. Field Goal Made (+3 points, kickoff- roughly opponent's own 25)
state_fg_make <- function(score_differnetial, timeouts_off, timeouts_def, game_seconds_remaining){
  #yardline = 75 approximates opponent starting around their own 25
  flipped <- flip_possession(75, score_differnetial + 3, timeouts_off, timeouts_def)
  c(list(down = 1,
         ydstogo = 10, 
         game_seconds_remaining = max(seconds_remaining - 5, 0)),
    flipped)
}


# 4. Field goal missed (possession flips at spot of kick, roughly 7 yards behind the line of scrimmage)
state_fg_miss <- function(yardline_100, score_differential, timeouts_off, timeouts_def, game_seconds_remaining){
  spot_of_kick <- min(yardline_100 + 7, 99) #clip near goal line
  flipped <- flip_possession(spot_of_kick, score_differential, timeouts_off, timeouts_def)
  c(list(down = 1, 
         ydstogo = 10, game_seconds_remaining,
         game_seconds_remaining = max(game_seconds_remaining -5, 0)),
    flipped)
}


# 5. Punt (possession flips, field position from punt model's predicted net_value_final)
state_punt <- function(yardline_100, score_differential, timeouts_off, timeouts_def, game_seconds_remaining, predicted_net_value){
  new_receiving_yardline <- 100 - (yardline_100 - predicted_net_value) # translate net value into new field position
  new_receiving_yardline <- min(max(new_receiving_yardline, 1), 99) #keep within bounds
  flipped <- flip_possession(100 - new_receiving_yardline, score_differential, timeouts_off, timeouts_def)
  c(list(down = 1,
         ydstogo = 10, 
         game_seconds_remaining = max(game_seconds_remaining -5, 0)),
    flipped)
}

#-----------------------------------------------------------------------------------------------------
## Placeholder values and helper functions for actual model
#-----------------------------------------------------------------------------------------------------
# Xpass placeholder by ydstogo bucket, from existing training data
xpass_lookup <- fourth_go %>%
  filter(!is.na(xpass)) %>%
  mutate(ydstogo_bucket = case_when(
    ydstogo <= 2 ~ "short",
    ydstogo <= 5 ~ "medium",
    ydstogo <= 10 ~ "long",
    TRUE ~ "very_long"
  )) %>%
  group_by(ydstogo_bucket) %>%
  summarize(avg_xpass = mean(xpass, na.rm = TRUE))

get_xpass_placeholder <- function(ydstogo, xpass_lookup) {
  bucket <- case_when(
    ydstogo <= 2 ~ "short",
    ydstogo <= 5 ~ "medium",
    ydstogo <= 10 ~ "long",
    TRUE ~ "very_long"
  )
  xpass_lookup$avg_xpass[xpass_lookup$ydstogo_bucket == bucket]
}

## League average statistics for kickers, punters, and returners
league_avg_kicker_season_fg_pct <- mean(fg_model_data$kicker_season_fg_pct, na.rm = TRUE)
league_avg_kicker_career_fg_pct <- mean(fg_model_data$kicker_career_fg_pct, na.rm = TRUE)
league_avg_kicker_long_made <- mean(fg_model_data$kicker_long_made, na.rm = TRUE)

league_avg_punter_gross <- mean(punt_model_data$punter_career_gross_avg, na.rm = TRUE)
league_avg_punter_net <- mean(punt_model_data$punter_career_net_avg, na.rm = TRUE)
league_avg_returner_impact <- mean(punt_model_data$returner_career_impact, na.rm = TRUE)

get_kicker_stats <- function(kicker_name, kicker_stats_table) {
  match <- kicker_stats_table %>%
    filter(kicker_player_name == kicker_name) %>%
    arrange(desc(game_id), desc(play_id)) %>%  # most recent known row for that kicker
    slice_head(n = 1)
  
  if (nrow(match) == 0) {
    # no record found -> fall back to league averages
    return(data.frame(
      kicker_season_fg_pct = league_avg_kicker_season_fg_pct,
      kicker_career_fg_pct = league_avg_kicker_career_fg_pct,
      kicker_long_made = league_avg_kicker_long_made
    ))
  }
  
  match %>% select(kicker_season_fg_pct, kicker_career_fg_pct, kicker_long_made)
}

get_punter_stats <- function(punter_name, punter_lookup_table) {
  match <- punter_lookup_table %>%
    filter(punter_player_name == punter_name) %>%
    arrange(desc(game_id), desc(play_id)) %>%
    slice_head(n = 1)
  
  if (nrow(match) == 0) {
    return(data.frame(
      punter_career_gross_avg = league_avg_punter_gross,
      punter_career_net_avg = league_avg_punter_net
    ))
  }
  
  match %>% select(punter_career_gross_avg, punter_career_net_avg)
}

# Build FG model input
build_fg_input <- function(yardline_100, 
                           qtr, 
                           game_seconds_remaining,
                           score_differential,
                           kicker_name,
                           kicker_stats_table,
                           weather_cat = "clear", #change later
                           indoor = 0,
                           surface = "grass"){
    
    kicker_info <- get_kicker_stats(kicker_name, kicker_stats_table)
    
    data.frame(
      kick_distance = yardline_100 + 17,
      yardline_100 = yardline_100,
      qtr = qtr,
      game_seconds_remaining = game_seconds_remaining,
      score_differential = score_differential,
      kicker_season_fg_pct = kicker_stats_table$kicker_season_fg_pct,
      kicker_career_fg_pct = kicker_stats_table$kicker_career_fg_pct,
      kicker_long_made = kicker_stats_table$kicker_long_made,
      weather_cat = weather_cat,
      indoor = indoor,
      surface = surface
    )
  }

#  Build the punt model input
build_punt_input <- function(yardline_100, punter_name, punter_stats_table, weather_cat = "clear", indoor = 0, surface = "grass", returner_career_impact = league_avg_returner_impact, no_returner = FALSE){
    punter_info <- get_punter_stats(punter_name, punter_stats_table)

    data.frame(
      yardline_100 = yardline_100,
      weather_cat = weather_cat,
      indoor = indoor,
      surface = surface,
      punter_career_gross_avg = punter_stats_table$punter_career_gross_avg,
      punter_career_net_avg = punter_stats_table$punter_career_net_avg,
      returner_career_impact = returner_career_impact,
      no_returner = no_returner
      )
    }




#-----------------------------------------------------------------------------------------------------
## Probability Weighting
#-----------------------------------------------------------------------------------------------------
# 1. Get the three model outputs for the current situation
get_conv_prob <- function(current_state){
  predict(conv_gam_model, newdata = current_state, type = "response")
}

get_fg_prob <- function(current_state){
  predict(fg_gam_model, newdata = current_state, type = "response")
}

get_punt_net_value <- function(current_state){
  predict(punt_gam_model, newdata = current_state, type = "response")
}


# 2. Run each constructed state through the wp model
get_win_prob <- function(state, wp_log_model){
  state_df <- as.data.frame(state)
  predict(wp_log_model, newdata = state_df, type = "response")
}



# 3. Make the actual Decision Function
evaluate_fourth_down <- function(down, ydstogo, yardline_100, score_differential, game_seconds_remaining, half_seconds_remaining, posteam_timeouts_remaining, defteam_timeouts_remaining, qtr, posteam_type, conv_gam_model, fg_gam_model, punt_gam_model, wp_log_model, fail_yards_lookup, kicker_name, punter_name){
  
# a. Get probabilities/predictions from each sub-model
  
  ## input varaibles for conversion
  conv_input <- data.frame(
    ydstogo = ydstogo,
    yardline_100 = yardline_100,
    score_differential = score_differential,
    half_seconds_remaining = half_seconds_remaining,
    qtr = qtr,
    posteam_timeouts_remaining = posteam_timeouts_remaining,
    defteam_timeouts_remaining = defteam_timeouts_remaining,
    goal_to_go = ifelse(yardline_100 <= 10, 1, 0),
    xpass = get_xpass_placeholder(ydstogo, xpass_lookup),
    posteam_type = posteam_type
  )
  
  ## probability of converting
  conv_prob <- get_conv_prob(conv_input)
    

  ## input variables for fg
  fg_input <- build_fg_input(
    yardline_100 = yardline_100,
    qtr = qtr,
    game_seconds_remaining = game_seconds_remaining,
    score_differential = score_differential,
    kicker_name = kicker_name,
    kicker_stats_table = kicker_stats
  )
  
  ## probability of field goal
  fg_prob <- get_fg_prob(fg_input)
    
  ## input variables for punt
  punt_input <- build_punt_input(
    yardline_100 = yardline_100, 
    punter_name = punter_name,
    punter_stats_table = punter_stats
  )
  
  ## expected net field position value
  punt_ev <- get_punt_net_value(punt_input)
  
  ## b. Build the resulting states
  
}
