# 4th-Down Decision Engine -- Methodology 

## 1. Main Goal

This project develops a computational model that evaluates NFL fourth-down decisions by integrating both traditional decision options (go, kick, punt) and clock-management strategies (milk, rush, timeout, delay, normal). The methodology outlines the data sources, feature engineering, model pipeline, simulation logic, and evaluation framework used to construct the decision engine.

On any 4th down, a coach is really choosing between three different bets, each with its own odds and its own payoff. Going for it bets on a conversion probability in exchange for a fresh set of downs (or a touchdown). Kicking a field goal bets on a make probability in exchange for a smaller, more certain 
payoff. Punting isn't a bet in the same sense — it trades the current down away entirely in exchange for better field position. A Win Probability model converts each of these bets into a common currency (expected win probability), allowing the three otherwise incomparable options to be directly compared.


## 2. Data Source

All data was sourced from the 'nflfastr' R package, which provides publicly available NFL play-by-play data. Seasons 2016–2023 were used, pulled via 'load_pbp()'. This includes situational variables (down, distance, field position, score, time, timeouts), play outcomes, and pre-computed advanced metrics such as 'xpass' (pre-snap pass probability).


## 3. Data Cleaning & Filtering

Each of the four core models required its own filtering and cleaning steps:

- **Conversion Model**: filtered to 4th-down run/pass attempts, with rows containing missing key predictors dropped.
- **Field Goal Model**: filtered to 4th-down field goal attemts (excluding extra points). Kicker career/season statistics were computed as cumulative, leakage-safe averages (using only attempts prior to the current row) to avoid using future information to predict past outcomes. Blank/missing "surface" values, along with inconsistent capitalization and whitespace (ex. "grass" vs. "grass "), were identified and standardized.
- **Punt Model**: required the most extensive cleaning. The outcome variable (net field-position value) was derived by joining each punt to the following play's starting field position. Rare edge cases (blocked punts not recovered by the punting team, muffed punts recovered by the punting team, and safeties) required special handling, since the standard field-position formula assumes possession changes hands normally. Safeties were excluded entirely (handled as a scoring event downstream), punting-team-recovery outcomes were assigned a representative constant value (20), derived from the 10th percentile of the corrected-sign distribution of similar plays, since there was insufficient data to model these cases separately with precision.
- **Win Probability Model**: built from the full, unfiltered play-by-play dataset (all downs, not just 4th), with each play labeled by whether the team in possession ultimately won that game. Ties were excluded.

Across all models, train/test splits were performed by season (earlier seasons for training, held-out recent seasons for testing) rather than random row-level splits, to prevent information leakage across a game or season and to better reflect real-world generalization to future, unseen seasons. 


## 4. Feature Engineering

- **Conversion Model**: down/distance, field position, score differential, time remaining, timeouts, 'goal_to_go', 'xpass', and possession type.
- **Field Goal Model**: kick distance (derived from field position), situational variables, kicker career/season FG percentage, kicker long made (all computed as leakage-safe cumulative statistics), and environmental variables (weather category, indoor/dome, surface).
- **Punt Model**: field position, environmental variables, and punter/returner career statistics (computed as leakage-safe cumulative averages of the model's own corrected outcome variable, net field-position value, rather than raw yardage, since the corrected variable more accurately reflects true field-position impact (accounting for touchbacks, fair catches, and the edge cases above)). A 'no_returner' flag was added to distinguish plays with no return (touchbacks, fair catches — roughly 32% of punts) from plays with a below-average returner, since these are distinct situations that a single imputed value would otherwise conflate.
- **Win Probability Model**: score differential, time remaining, field position, down, distance, timeouts, quarter, and possession type (home/away), including a score-differential-by-time-remaining interaction term, since the value of a given lead depends heavily on how much time remains.


## 5. Modeling Framework

Each of the four core models compares two candidate approaches: a simpler, linear/additive model against a more flexible Generalized Additive Model (GAM) capable of learning nonlinear relationships. This comparison was run consistently across all four models to test whether the added flexibility of a GAM was empirically justified, rather than assumed.

| Model | Candidate Models | Target | Metrics |
|---|---|---|---|
| Conversion | Logistic Regression vs. GAM | Binary (converted or not) | AUC, Log Loss, Brier Score |
| Field Goal | Logistic Regression vs. GAM | Binary (made or missed) | AUC, Log Loss, Brier Score |
| Punt | Linear Regression vs. GAM | Continuous (net field-position value) | RMSE, MAE |
| Win Probability | Logistic Regression vs. GAM | Binary (won or lost) | AUC, Log Loss, Brier Score |

All models were fit exclusively on training-season data and evaluated on held-out, more recent seasons the model never saw during fitting. 


## 6. Clock-Management Simulation Layer

A supplementary layer evaluates five clock-management strategies:
- Milk (using up to 39 seconds of the play clock before snapping)
- Delay of game (deliberately taking a delay-of-game penalty to burn additional time, at a 5-yard field-position cost)
- Rush (hurry-up tempo, minimal time per play)
- Timeout (stopping the clock at the cost of a team timeout)
- Normal (baseline tempo)

These strategies were assembled by simulating each strategy's effect on remaining game time (and, for Delay, field position), then evaluating the resulting state through the Win Probability model. Strategies are ranked by resulting expected win probability. 


## 7. Decision Engine

For any 4th-down situation, the engine constructs the hypothetical resulting game state for each of the three primary options (go for it, kick, punt), using the outputs of the conversion, field goal, and punt models respectively. Each resulting state is evaluated through the Win Probability model. For go-for-it and field goal (binary outcomes), the resulting states for both success and failure are computed and combined, weighted by the relevant success probability, into a single expected win probability. Punt, having no binary success/failure split, uses the punt model's expected net field-position value directly. The option with the highest expected win probability is the engine's recommendation.


## 8. Evaluation

Out-of-sample results across all four core models:

| Model | Metric | Logistic/Linear | GAM |
|---|---|---|---|
| Conversion | AUC | 0.6793 | 0.6837 |
| Conversion | Log Loss | 0.6354 | 0.6334 |
| Conversion | Brier Score | 0.2227 | 0.2219 |
| Field Goal | AUC | 0.7423 | 0.7448 |
| Field Goal | Log Loss | 0.3643 | 0.3604 |
| Field Goal | Brier Score | 0.1130 | 0.1116 |
| Punt | RMSE | 10.49 | 10.26 |
| Punt | MAE | 7.21 | 6.94 |
| Win Probability | AUC | 0.8131 | 0.8136 |
| Win Probability | Log Loss | 0.5223 | 0.5229 |
| Win Probability | Brier Score | 0.1762 | 0.1760 |

Conversion, Field Goal, and Punt all favor the GAM, with the advantage holding and slightly increasing out-of-sample. The Win Probability model was the exception: logistic regression and the GAM performed nearly identically, confirmed further by a calibration check across the full probability range showing near-identical tracking between the two, including in the 0.4-0.6 range representing close, competitive games. Logistic regression was selected for the final Win Probability model given comparable performance and greater simplicity. 

The fully assembled engine was additionally validated against four hand-constructed scenarios chosen for having intuitively clear (or interestingly non-obvious) correct answers:

1. 4th and 1 from the opponent's 2, tied game -- correctly recommended going for it.
2. 4th and 8 from the opponent's 25, tied game -- recommended going for it over a highly makeable field goal, consistent with published research suggesting coaches are often too conservative in these spots.
3. 4th and 10 from their own 20 -- correctly recommended punting.
4. 4th and 3 from the opponent's 30, trailing by 3 with 90 seconds left -- correctly recommended a field goal to tie the game, after a limitation fix described below corrected an earlier, clearly wrong recommendation.

The clock-management layer was validated similarly: strategy rankings correctly favored clock-burning strategies (Milk) when protecting a lead late in the game, and tempo-preserving strategies (Rush) when trailing late. 


## 9. Limitations

End-to-end engine testing, rather than model-level metrics alone, surfaced two real limitations in the underlying models:

- **Field goal reliability at high yardline_100 values.** The field goal model, while well-calibrated within its training range, was found through engine testing to produce a competitive-looking expected value for a 72-yard attempt (outside the range of any observed training data -- max = 67 yards) despite a correctly low predicted make probability (9.3%). This reflects a limitation of relying on a single low, but nonzero probability without an explicit realism constraint. The engine now restricts field goal evaluation to kick distances <= 60 yards. 
- **Punt model reliability at low "yardline_100" values.** Visual inspection of the model's smooth terms revealed an implausible relationship between field position and expected punt value near the opponent's goal line (a region where real punt attempts are extremely rare -- only 5% of historical punts occurred below "yardline_100 = 42"). The engine now restricts punt evaluation to "yardline_100 >= 45", both reflecting realistic in-game behavior and avoiding the model's least reliable operating region.
- **Conversion model calibration in rare situations.** The model overestimates conversion probability for the uncommon combination of long distance-to-go and deep own-territory field data (n = 46 in one tested case) and roughly a 10-percentage-point overestimate relative to the historical rate.
- **Clock-management Timeout strategy.** Consistently underperforms in testing, since the current model evaluates it purely on time-tradeoff terms rather than capturing its primary real-world value, guaranteeing an additional play is possible before the clock expires.
- **Data generality.** This project is built entirely on nflfastR's play-by-play data, which describes what happened on a play in aggregate (down, distance, yards gained) without describing who specifically drove that outcome. A more complete conversion model would ideally account for offensive personnel (a team's success rate on 4th-and-2 likely depends meaningfully on which quarterback, o-line, and receivers are on the field, not just situational variables. Relatedly, NFL Next Gen Stats' player-tracking data (capturing actual player movement, positioning, and separation rather than just play outcomes) would meaningfully improve on what's possible with play-by-play data alone and is a natural direction for future extension. 
- **Weather effects on field goal probability** are well-supposed for common conditions (clear, cloudy, rain), but conditions with limited historical representation (particularly snow and fog, with 49 and 22 recorded cases respectfully) show muted, less confident effects. This is likely reflecting insufficient data to estimate a distinct impact rather than these conditions genuinely having little effect on kicking. 

## 10. Ethical & Practical Considerations

All data obtained for this project is publicly available. No personal or private player information is used. This model is intended for research and educational purposes only. 
