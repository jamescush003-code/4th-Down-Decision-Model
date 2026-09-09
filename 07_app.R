#Basic skeleton of app
library(shiny)
library(mgcv)
library(dplyr)
library(shinyjs)
library(ggplot2)

# Load trained models
conv_gam_model <- readRDS("models/conv_gam_model.rds")
fg_gam_model   <- readRDS("models/fg_gam_model.rds")
punt_gam_model <- readRDS("models/punt_gam_model.rds")
wp_log_model   <- readRDS("models/wp_log_model.rds")

# Load lookup tables
fail_yards_lookup <- readRDS("models/fail_yards_lookup.rds")
xpass_lookup       <- readRDS("models/xpass_lookup.rds")

message("xpass_lookup class: ", class(xpass_lookup))
message("xpass_lookup rows: ", nrow(xpass_lookup))
message("xpass_lookup columns: ", paste(names(xpass_lookup), collapse = ", "))

kicker_stats       <- readRDS("models/kicker_stats.rds")
punter_stats       <- readRDS("models/punter_stats.rds")

# Load league-average constants
league_avg_kicker_season_fg_pct <- readRDS("models/league_avg_kicker_season_fg_pct.rds")
league_avg_kicker_career_fg_pct <- readRDS("models/league_avg_kicker_career_fg_pct.rds")
league_avg_kicker_long_made     <- readRDS("models/league_avg_kicker_long_made.rds")
league_avg_punter_gross         <- readRDS("models/league_avg_punter_gross.rds")
league_avg_punter_net           <- readRDS("models/league_avg_punter_net.rds")
league_avg_returner_impact      <- readRDS("models/league_avg_returner_impact.rds")

# Load engine functions
source("decision.engine.R", local = TRUE)
message("get_xpass_placeholder exists: ", exists("get_xpass_placeholder"))


#UI
ui <- fluidPage(
  useShinyjs(),
  titlePanel("4th Down Decision Engine"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Game Situation"),
      
      numericInput("ydstogo", "Yards to Go", value = 3, min = 1, max = 30),
      
      numericInput("yardline_100", "Yards from Opponent's End Zone", value = 50, min = 1, max = 99),
      
      numericInput("score_differential", "Score Differential (your team - opponent)", value = 0, min = -50, max = 50),
      
      selectInput("weather_cat", "Weather Conditions", 
                  choices = c("Clear" = "clear", "Cloudy" = "cloudy", "Rain" = "rain", "Snow" = "snow", "Fog" = "fog"),
                  selected = "clear"),
      
      selectInput("indoor", "Indoor/Dome Game?", 
                  choices = c("No" = "0", "Yes" = "1"),
                  selected = "0"),
      
      selectInput("qtr", "Quarter", choices = c(1, 2, 3, 4), selected = 1),
      
      numericInput("seconds_left_in_quarter", "Seconds Remaining in Quarter", value = 900, min = 0, max = 900),
      
      numericInput("posteam_timeouts_remaining", "Your Timeouts Remaining", value = 3, min = 0, max = 3),
      
      numericInput("defteam_timeouts_remaining", "Opponent Timeouts Remaining", value = 3, min = 0, max = 3),
      
      selectInput("posteam_type", "Possession Team", choices = c("home", "away")),
      
      selectInput("kicker_name", "Kicker", 
                  choices = sort(unique(kicker_stats$kicker_player_name)),
                  selected = "J.Tucker"),
      helpText("Format: First initial. Last name (e.g., J.Tucker)"),
      
      selectInput("punter_name", "Punter",
                  choices = sort(unique(punter_stats$punter_player_name))),
      helpText("Format: First initial. Last name (e.g., J.Someone)"),
      
      actionButton("evaluate", "Evaluate 4th Down", class = "btn-primary"),
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("4th Down Decision", uiOutput("main_output")),
        tabPanel("Clock Management", uiOutput("clock_output"))
      )
    )
  )
)



# Server
server <- function(input, output, session) {
  
  # Compute shared derived time values
  derived_time <- eventReactive(input$evaluate, {
    qtr_num <- as.numeric(input$qtr)
    quarters_remaining_after_this_one <- 4 - qtr_num
    list(
      qtr_num = qtr_num,
      game_seconds_remaining = input$seconds_left_in_quarter + (quarters_remaining_after_this_one * 900),
      half_seconds_remaining = if (qtr_num %in% c(1, 3)) {
        input$seconds_left_in_quarter + 900
      } else {
        input$seconds_left_in_quarter
      }
    )
  })
  
  observe({
    if (input$indoor == "1") {
      disable("weather_cat")
      updateSelectInput(session, "weather_cat", selected = "clear")  # force to a neutral value while disabled
    } else {
      enable("weather_cat")
    }
  })
  
  
  #Use derived_time(), calls evaluate_fourth_down()
  eval_result <- eventReactive(input$evaluate, {
    
    # Validation: catch bad input before running the engine 
    
    validate(
      need(input$ydstogo <= input$yardline_100,
           "Yards to go can't exceed distance from the end zone.")
    )
    
    dt <- derived_time()
    
    # Call existing engine with the derived values 
    evaluate_fourth_down(
      ydstogo = input$ydstogo,
      yardline_100 = input$yardline_100,
      score_differential = input$score_differential,
      game_seconds_remaining = dt$game_seconds_remaining,
      half_seconds_remaining = dt$half_seconds_remaining,
      posteam_timeouts_remaining = input$posteam_timeouts_remaining,
      defteam_timeouts_remaining = input$defteam_timeouts_remaining,
      qtr = dt$qtr_num,
      posteam_type = input$posteam_type,
      kicker_name = input$kicker_name,
      punter_name = input$punter_name,
      weather_cat = input$weather_cat,
      indoor = as.numeric(input$indoor)
    )
  })
  
  # Output renderers
  clock_result <- eventReactive(input$evaluate, {
    
    dt <- derived_time()  # <- calling reactive #1 again from a different reactive
    evaluate_clock_management(
      down = 4,
      ydstogo = input$ydstogo,
      score_differential = input$score_differential,
      yardline_100 = input$yardline_100,
      game_seconds_remaining = dt$game_seconds_remaining,
      posteam_timeouts_remaining = input$posteam_timeouts_remaining,
      defteam_timeouts_remaining = input$defteam_timeouts_remaining,
      qtr = dt$qtr_num,
      posteam_type = input$posteam_type
    )
  })
  
  
  # Output renderers
  output$main_output <- renderUI({
    result <- eval_result()
    
    results_display <- result$results
    results_display$option <- ifelse(
      results_display$option == result$recommendation,
      paste0("<b>", results_display$option, " ✓</b>"),
      results_display$option
    )
    
    tagList(
      h4("Recommendation"),
      p(em("**Values shown are estimated win probability for the overall game if this option is chosen, not the standalone chance of success on this specific play**")),
      p(strong(result$recommendation)),
      HTML(renderTable(results_display, sanitize.text.function = function(x) x, digits = 6)()),
      plotOutput("main_chart"),
      if (any(!is.finite(result$results$expected_win_prob))) {
        p(em("Note: one or more options were excluded as unrealistic for this field position (see chart/table)."))
      }
    )
  })

      
  output$main_chart <- renderPlot({
    result <- eval_result()
    chart_data <- result$results %>%
      filter(is.finite(expected_win_prob))
    
    ggplot(chart_data, aes(x = option, y = expected_win_prob, fill = option == result$recommendation)) +
      geom_col() +
      scale_fill_manual(values = c("TRUE" = "#2E8B57", "FALSE" = "#B0B0B0"), guide = "none") +
      labs(x = NULL, y = "Expected Win Probability", title = NULL) +
      ylim(0, 1) +
      theme_minimal(base_size = 14)
  })
  
  
  
  output$clock_output <- renderUI({
    result <- clock_result()
    clock_display <- result
    clock_display$strategy <- ifelse(
      clock_display$strategy == result$strategy[1],
      paste0("<b>", clock_display$strategy, " ✓</b>"),
      clock_display$strategy
    )
    
    tagList(
      h4("Best Clock Strategy"),
      p(em("**Values shown are estimated win probability for the overall game under each clock strategy, not a measure of how likely the strategy is to be executed successfully**")),
      p(strong(paste("Recommended:", result$strategy[1]))),
      HTML(renderTable(clock_display, sanitize.text.function = function(x) x, digits = 5)()),
      plotOutput("clock_chart"),
      p(em("Note: clock-management strategies often produce closely-valued outcomes: small differences here can still reflect a meaningfully better choice over the course of a game."))
    )
  })
  
  
  output$clock_chart <- renderPlot({
    result <- clock_result()
    
    ggplot(result, aes(x = strategy, y = expected_win_prob, fill = strategy == result$strategy[1])) +
      geom_col() +
      scale_fill_manual(values = c("TRUE" = "#2E8B57", "FALSE" = "#B0B0B0"), guide = "none") +
      labs(x = NULL, y = "Expected Win Probability", title = NULL) +
      ylim(0, 1) +
      theme_minimal(base_size = 14)
  })
}

#Run App
shinyApp(ui, server)
