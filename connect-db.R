library(DBI)
filepath <- "listings.db"
# Sets an SQLite database connection
dbcon <- dbConnect(odbc::odbc(), 
                   driver = "SQLite3",
                   database="data/listings.db")

table_names <- DBI::dbListTables(dbcon)

message("connected: ", filepath, " (", length(table_names), " tables)")
for (table in table_names) {
  query <- sqlInterpolate(
    dbcon,
    "SELECT COUNT(*) from ?table",
    table = table)
  
  message("\t", table, ": ", dbGetQuery(dbcon, query), " rows")
}