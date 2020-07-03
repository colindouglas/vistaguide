cd data

for f in listings_*.csv; do
  mv -- "$f" "$(basename -- "$f" .csv).done"
done
