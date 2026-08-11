## Filter Data

# Determine the final score for each game and then label each play by whether 
# the offense (posteam) ultimately won the game
final_scores <- pbp %>%
  filter(!is.na(result)) %>%    # result = home - away, final margin
  distinct(game_id, home_team, away_team, result) %>%
  mutate(winning_team = case_when(
    result > 0 ~ home_team, 
    result < 0 ~ away_team, 
    TRUE ~ "TIE"
  ))

# Join in the variable if the offense won the game
wp_model_data <- pbp %>%
  left_join(final_scores %>% select(game_id, winning_team), by = "game_id") %>%
  filter(
    winning_team != "TIE", # drop ties; makes it awkward for binary target
    !is.na(posteam),
    !is.na(score_differential),
    !is.na(game_seconds_remaining),
    !is.na(yardline_100),
    !is.na(down)
  ) %>%
  mutate(
    win = ifelse(posteam == winning_team, 1, 0)
  ) %>%
  select(
    game_id, season, win,
    score_differential, game_seconds_remaining, yardline_100,
    down, ydstogo,
    posteam_timeouts_remaining, defteam_timeouts_remaining, qtr, posteam_type
  )

# train/test split
wp_train <- wp_model_data %>%
  filter(season <= 2021)
wp_test <- wp_model_data %>%
  filter(season > 2021)

## Create Models & Compare

# Logistic Regession Model
wp_log_model <- glm(
  win ~ score_differential +
    game_seconds_remaining +
    yardline_100 +
    down +
    ydstogo +
    posteam_timeouts_remaining +
    defteam_timeouts_remaining +
    posteam_type +
    qtr +
    score_differential:game_seconds_remaining,
  data = wp_train,
  family = binomial
)

# GAM
wp_gam_model <- gam(
  win ~ s(score_differential) +
    s(game_seconds_remaining) +
    s(yardline_100) +
    down + 
    s(ydstogo) + 
    posteam_timeouts_remaining + 
    defteam_timeouts_remaining +
    qtr +
    posteam_type +
    ti(score_differential, game_seconds_remaining),
  data = wp_train, family = binomial
)


wp_log_preds <- predict(wp_log_model, newdata = wp_test, type = "response")
wp_gam_preds <- predict(wp_gam_model, newdata = wp_test, type = "response")

#AUC values
wp_auc_log <- roc(wp_test$win, wp_log_preds)$auc
wp_auc_gam <- roc(wp_test$win, wp_gam_preds)$auc

#Log Loss
  # fix the equation to clip predictions away from the exact 0/1 boundary before computing
log_loss <- function(actual, predicted, eps = 1e-15) {
  predicted <- pmin(pmax(predicted, eps), 1 - eps)
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}

wp_ll_log <- log_loss(wp_test$win, wp_log_preds)
wp_ll_gam <- log_loss(wp_test$win, wp_gam_preds)

#Brier scores
wp_brier_log <- mean((wp_test$win - wp_log_preds)^2)
wp_brier_gam <- mean((wp_test$win - wp_gam_preds)^2)

wp_auc_log
wp_auc_gam
wp_ll_log
wp_ll_gam
wp_brier_log
wp_brier_gam

# Extra check for calibration of the two models to see if there's a real difference\
wp_cal_log <- wp_test %>%
  mutate(pred = wp_log_preds, bin = ntile(pred, 10)) %>%
  group_by(bin) %>%
  summarize(mean_pred = mean(pred), mean_actual = mean(win))

wp_cal_gam <- wp_test %>%
  mutate(pred = wp_gam_preds, bin = ntile(pred, 10)) %>%
  group_by(bin) %>%
  summarize(mean_pred = mean(pred), mean_actual = mean(win))


  # Plot calibrations against the diagonal
bind_rows(
  wp_cal_log %>% mutate(model = "Logistic"),
  wp_cal_gam %>% mutate(model = "GAM")
) %>%
  ggplot(aes(x = mean_pred, y = mean_actual, color = model)) +
  geom_point(size = 2) +
  geom_line() +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "gray40") +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(
    title = "Win Probability Model Calibration",
    x = "Predicted win probability (bin average)",
    y = "Actual win rate (bin average)"
  )
