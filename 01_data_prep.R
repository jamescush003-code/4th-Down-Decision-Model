# Load datasets and libraries
library(nflfastR)
library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)
library(mgcv) # Works for GAM model
library(pROC) # Compare AUC values

# Filter data for only 4th down plays
pbp <- load_pbp(2016:2023)
fourth <- pbp %>% filter(down == 4)
