# Re-render all of the outputs with the current dataset
# all == c("html", "markdown")
rmarkdown::render("analysis.Rmd", output_format = "all")
