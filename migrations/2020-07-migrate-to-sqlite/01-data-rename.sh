cd ~/projects/vistaguide/data || exit

for f in listings_*.csv; do
  mv -- "$f" "$(basename -- "$f" .csv).done"
done
