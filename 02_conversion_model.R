# Filter data for only plays that try to convert on 4th down
fourth_go <- fourth %>%
  filter(play_type %in% c("run", "pass")) %>%
  
  # Create outcome variable (convert)
  mutate(convert = ifelse(first_down == 1, 1, 0))

# Features in model
conv_model_data <- fourth_go %>%
  select(
    convert,
    ydstogo,
    yardline_100,
    score_differential,
    half_seconds_remaining,
    qtr,
    posteam_timeouts_remaining,
    defteam_timeouts_remaining,
    goal_to_go,
    xpass,
    posteam_type,
    season
  ) %>%
  drop_na()

# Training data = seasons before 2022, test is seasons after (2022, 
train_data <- conv_model_data %>%
  filter(season <= 2021)
test_data <- conv_model_data %>%
  filter(season > 2021)

## Build Logistic Regression & GAM Models
#Logistic Regression Model
conv_log_model <- glm(
  convert ~ ydstogo +
    yardline_100 +
    score_differential +
    half_seconds_remaining +
    qtr +
    posteam_timeouts_remaining +
    defteam_timeouts_remaining +
    goal_to_go +
    xpass +
    posteam_type +
    ydstogo:yardline_100 +
    ydstogo:score_differential +
    ydstogo:half_seconds_remaining +
    yardline_100:half_seconds_remaining +
    score_differential:qtr,
  data = train_data,
  family = binomial
)

#GAM Model (interactions handled implicitly)
conv_gam_model <- gam(
  convert ~ s(ydstogo) +
    s(yardline_100) +
    s(score_differential) +
    s(half_seconds_remaining) +
    qtr +
    posteam_timeouts_remaining +
    defteam_timeouts_remaining +
    goal_to_go +
    xpass +
    posteam_type,
  data = train_data,
  family = binomial
)

## Compare the Models
#Generate Prediction Probabilities for each Model
log_preds <- predict(conv_log_model, newdata = test_data, type = "response")
gam_preds <- predict(conv_gam_model, newdata = test_data, type = "response")


#Add variables to dataset
test_data <- test_data %>%
  mutate(
    log_pred = log_preds,
    gam_pred = gam_preds
  )

#Compare AUC
auc_log <- roc(test_data$convert, test_data$log_pred)$auc
auc_gam <- roc(test_data$convert, test_data$gam_pred)$auc
auc_log
auc_gam

#Compare Log-Loss (Probability Accuracy)
log_loss <- function(actual, predicted) {
  -mean(actual * log(predicted) + (1 - actual) * log(1 - predicted))
}
ll_log <- log_loss(test_data$convert, test_data$log_pred)
ll_gam <- log_loss(test_data$convert, test_data$gam_pred)
ll_log
ll_gam

#Calibration Curves (Probability Realism)
#Logistic Model Calibration
cal_log <- test_data %>%
  mutate(bin = ntile(log_pred, 10)) %>%
  group_by(bin) %>%
  summarize(
    mean_pred = mean(log_pred),
    mean_actual = mean(convert)
  )

cal_gam <- test_data %>%
  mutate(bin = ntile(gam_pred, 10)) %>%
  group_by(bin) %>%
  summarize(
    mean_pred = mean(gam_pred),
    mean_actual = mean(convert)
  )

conv_brier_score_log <- mean((test_data$convert - test_data$log_pred)^2)
conv_brier_score_gam <- mean((test_data$convert - test_data$gam_pred)^2)
conv_brier_score_log
conv_brier_score_gam

# Across all of the evaluation metrics, the GAM model demonstrated slightly 
# stronger performance when compared to the logistic regression model, indicating 
# that fourth-down conversion probability is driven by non-linear relationships that 
# a GAM model is better suited to capture. The GAM achieved a higher AUC (0.6789 vs. 0.6777), 
# meaning it was marginally better suited for distinguishing successful conversions from failures. 
# It also produced a lower log-loss (0.638 vs. 0.639), showing that its predicted probabilities were 
# more accurate and less overconfident when wrong. When looking at calibration analysis, this idea is 
# backed up further, with the GAM model yielding a lower Brier Score (0.2241 vs. 0.2242), reflecting 
# probabilities that are more closely matched to actual conversion rates. Although the differences are 
# small, they consistently favor the GAM model, which suggests that its ability to learn leads to more 
# reliable and better-calibrated estimates, which is a key advantage for the decision-making engine where 
# probability accuracy directly informs coaching strategy.
