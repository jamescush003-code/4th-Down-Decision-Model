# Load datasets and libraries

library(nflfastR)
library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)

# Works for GAM model
library(mgcv)

# Compare AUC values
library(pROC)

# Filter data for only 4th down plays
pbp <- load_pbp(2016:2023)
fourth <- pbp %>% filter(down == 4)
