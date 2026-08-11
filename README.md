# 4th-Down-Decision-Model

A 4th-down decision engine built on nflfastR data — separate models for conversion, field goal, and punt outcomes feeding into a win-probability comparison, with a clock-management layer on top.

## Main Goal

On any 4th-down scenario, this project plans to accurately tell a coach which option (go for it, kick a field goal, or punt) gives their team the best chance of winning the game, including how clock-management affects that decision (bleeding clock, rushing a snap, etc.). 

## Plan

### 1. Make three separate models to predict what's most likely to happen for one specific choice. Those options are:

- **Conversion Model:** If they go for it, what's the probability they succeed?

- **Field Goal Model:** If they kick, what's the probability it's good?

- **Punt Model:** If they punt, where does the ball realistically end up?

For a couple of rare-cases when considering the punting model (think blocked punt where the punting team doesn't recover, muffed punt where they do, etc.), the normal "field position formula" doesn't really apply since possession doesn't change hands the way it normally does. There wasn't enough data to model those cases separately with real precision, so I used representative constants pulled from the actual distribution of similar plays (strongly negative value for the bad case, a positive one for the recovery case) rather than letting the formula produce a misleading number.

### 2. Create a **"Win Probability"** model where the actual decision gets made (turning the idea of "what happens" to "how much does this help/hurt the chances of winning").

- Takes down distance, field position, score, time remaining, timeouts and the outputs of the three models from step 1 to convert each possible outcome into a single win probability if this certain scenario happens.

### 3. Create an engine with the win probability model that compares the win probabilities for the team if:

- They go for it and convert X conversion probability plus the win probability if they go for it and fail X (1- conversion probability)

- They attempt the field goal and make it X field goal probability **plus** win probability if they miss X (1- field goal probability)

- They punt the ball, giving the expected resulting field position.

**Whichever of the three expected values is highest is the model's recommendation.**

- Integrate a clock-management feature on top of this, which recognizes what the offense should do with the time they have (take a delay of game to bleed clock, rush to snap, etc.). this changes the value of time itself in certain situations, which shifts the win probability calculation slightly, but is still meaningful.

## Status

- [x] Conversion model (logistic regression vs. GAM, validated out-of-sample)
- [x] Field goal model (logistic regression vs. GAM, validated out-of-sample)
- [X] Punt model (linear regression vs. GAM, validated out-of-sample)
- [X] Win probability model
- [ ] Decision engine
- [ ] Clock-management layer
- [ ] Interactive app

## Methodology

Each model is validated using a season-based train/test split (train on earlier seasons, test on held-out recent seasons) rather than in-sample evaluation to ensure generalized results. 

The Conversion, Field Goal, and Win Probability models compare logistic regression against GAMs using AUC, log loss, and Brier score, while the Punt model compares linear regression against GAMs using RMSE and MAE values. The Conversion, Field Goal, and Punt models currently favor the GAM with the advantage holding and slightly increasing out-of-sample. Below are the calculated results for each model:

| Model | Metric | Logistic/Linear | GAM |
|---|---|---|---|
| Conversion | AUC | 0.6793 | 0.6837 |
| Conversion | Log Loss | 0.635 | 0.633 |
| Conversion | Brier Score | 0.223 | 0.222 |
| Field Goal | AUC | 0.7423 | 0.7448 |
| Field Goal | Log Loss | 0.3643 | 0.3604 |
| Field Goal | Brier Score | 0.113 | 0.112 | 
| Punt | RMSE | 10.49 | 10.26 |
| Punt | MAE | 7.21 | 6.94 | 
| Win Prob. | AUC | 0.8131 | 0.8136 |
| Win Prob. | Log Loss | 0.5223 | 0.5228 |
| Win Prob. | Brier Score | 0.1762 | 0.1760 |

The Win Probability model was the one exception: logistic regression and the GAM performed nearly identically (AUC 0.8131 vs. 0.8136, log loss 0.5223 vs. 0.5229, Brier 0.1762 vs. 0.1760), with the GAM narrowly winning two of three metrics but by margins too small to be meaningful. A calibration check across the full probability range (comparing predicted win probability against actual win rate in ten bins) confirmed the two models track almost identically, including in the mid (0.4-0.6) range representing close, competitive games, which matters most for the model's real-world use. Logistic regression was selected for the final Win probability model on this basis, given comparable performance and greater simplicity. 

![Win Probability Calibration](results/wp_calibration.png)
