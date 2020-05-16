.libPaths("/home/colin/R/x86_64-pc-linux-gnu-library/4.0")

library(knitr)
library(rmarkdown)

# Update the analysis markdown to HTML and to markdown
rmarkdown::render("analysis.Rmd", output_file = "analysis.md")

body <- readLines("analysis.md")
body <- c(
"---",
"title: ViewPointer",
"permalink: /viewpointer/",
"layout: page",
"excerpt: Aggregated data on Nova Scotia real estate listings",
"comments: false",
"---", "", body)

write(body, file = "analysis.md")