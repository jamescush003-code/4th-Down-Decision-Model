# 4th-Down-Decision-Model

A 4th-down decision engine built on nflfastR data — separate models for conversion, field goal, and punt outcomes feeding into a win-probability comparison, with a clock-management layer on top.

**Try it live: [https://jaycush-03.shinyapps.io/4th-down-decision-engine/]**

## Main Goal

On any 4th-down scenario, this project accurately tells a coach which option (go for it, kick a field goal, or punt) gives their team the best chance of winning the game, including how clock-management affects that decision (bleeding clock, rushing a snap, etc.). 

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

- [X] Conversion model (logistic regression vs. GAM, validated out-of-sample)
- [X] Field goal model (logistic regression vs. GAM, validated out-of-sample)
- [X] Punt model (linear regression vs. GAM, validated out-of-sample)
- [X] Win probability model
- [X] Decision engine
- [X] Clock-management layer
- [X] Interactive app

## Running Locally
The trained models (`.rds` files) are not included in this repository due to file size (they must be generated locally before the app can run). 

1. Run `01_data_prep.R` through `05_win_probability_model.R` to pull data and train all models (requires `nflfastR`, several seasons, may take a few minutes).
2. Run the `saveRDS()` steps at the end of the modeling notebook to save trained models and lookup tables to `models/`.
3. Open `app.R` and run it — this loads the saved models and launches the app locally.

**Or skip local setup entirely and use the live version: [https://jaycush-03.shinyapps.io/4th-down-decision-engine/]**

## Methodology
See `docs/methodology.md` for full details on data sources, model comparisons, validation results, known limitations, and the reasoning behind the decision engine and clock-management layer.

Full validation results across all four models, and details on two guardrails added after engine-level testing (the punt model's unreliable low-yardline region, and the field goal model producing an unrealistic recommendation at extreme kick distances), are documented there.

## A Note on Deployment
Deploying this app to shinyapps.io surfaced two subtle bugs that didn't appear during local testing, both worth noting as a real part of this project's development:
- **Environment scoping:** `source()`'s default behavior loads code into the global environment, which on a deployed server is separate from the environment holding the loaded models and data — fixed with `source("decision.engine.R", local = TRUE)`.
- **An implicit library dependency:** `ggplot2` was being loaded automatically through the local development session and was never explicitly declared, causing chart rendering to fail only once deployed to a clean environment.

Both were diagnosed using shinyapp.io's server logs (`rsconnect::showLogs()`) rather than guesswork. This was a good reminder that "works locally" and "works when deployed" aren't the same thing, even when the code looks identical. 
