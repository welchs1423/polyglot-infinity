.libPaths(c("~/R/library", .libPaths()))
library(plumber)

args      <- commandArgs(trailingOnly = FALSE)
file_arg  <- grep("--file=", args, value = TRUE)
script_dir <- dirname(normalizePath(sub("--file=", "", file_arg)))

pr <- plumb(file.path(script_dir, "server.R"))
pr$run(host = "0.0.0.0", port = 8003)

