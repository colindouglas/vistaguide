peninsula_codes <- c("B3H" = "South End", 
                     "B3J" = "Downtown", 
                     "B3K" = "North End", 
                     "B3L" = "West End")

hrm_places <- c("Halifax", "Dartmouth", "Bedford", "Lower Sackville", "Hammonds Plains", 
                "Beaver Bank", "Timberlea", "Middle Sackville", "Upper Sackville",
                "Lucasville", "Fall River", "Spryfield")

hrm_postals <- c(
  paste0("B2", LETTERS[22:26]),
  paste0("B3", LETTERS),
  paste0("B4", LETTERS[1:7])
)

status_colors <- c("For Sale" = "#3288bd", # Blue
                   "Pending" =  "#fdae61", # Yellow
                   "Sold" = "#5aae61", # Green
                   "Cancelled" = "#d53e4f", # Less dark red
                   "Withdrawn" = "#9e0142", # Dark Red
                   "Defunct" = "#6a3d9a", # Purple
                   "Expired" = "darkgrey")

type_order <- c("Single Family", "Condominium", "Mobile", "Land", "Multiplex",  
                "Cottage", "Commercial", "Industrial", "Other")
