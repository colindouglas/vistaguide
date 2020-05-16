library(knitr)
library(rmarkdown)

# What format should the public-facing analysis be in?
format <- "html"

if (format == "md") {
  rmarkdown::render("analysis.Rmd", output_file = "analysis.md", output_format = "md_document")
  
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
  
  system("./update-public.sh md")
  
}  else if (format == "html") {
  
  # Update the analysis markdown to HTML
  rmarkdown::render("analysis.Rmd", output_file = "analysis.html", output_format = "html_document")
  system("./update-public.sh html")
}