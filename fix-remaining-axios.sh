#!/bin/bash

# Find all files that import axiosInstance but still use axios
files=$(grep -l "import axiosInstance" /Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/*.ts | xargs grep -l "axios\.")

for file in $files; do
  echo "Fixing $file"
  # Replace axios. with axiosInstance.
  sed -i '' 's/\baxios\./axiosInstance./g' "$file"
done

echo "Fixed $(echo "$files" | wc -l) files"