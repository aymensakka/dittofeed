#!/bin/bash

# Find all files with axios.* calls
echo "Finding all files with direct axios calls..."
FILES=$(grep -r "axios\.\(get\|post\|put\|delete\|patch\|request\)" "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src" --include="*.ts" --include="*.tsx" -l)

for file in $FILES; do
  echo "Processing: $file"
  
  # Check if axiosInstance is already imported
  if ! grep -q 'import.*axiosInstance.*from.*["\047]\..*\/axiosInstance["\047]' "$file"; then
    echo "  Adding axiosInstance import..."
    
    # Get the relative path for the import
    dir=$(dirname "$file")
    rel_path=$(realpath --relative-to="$dir" "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib" 2>/dev/null || echo "./lib")
    
    # For files in lib directory
    if [[ "$file" == *"/lib/"* ]]; then
      import_path="./axiosInstance"
    # For files in pages directory  
    elif [[ "$file" == *"/pages/"* ]]; then
      import_path="../lib/axiosInstance"
    # For files in components directory
    elif [[ "$file" == *"/components/"* ]]; then
      import_path="../lib/axiosInstance"
    else
      import_path="./lib/axiosInstance"
    fi
    
    # Add import after the last import statement
    awk -v imp="import axiosInstance from \"$import_path\";" '
      /^import/ { imports = imports $0 "\n"; next }
      !printed && !/^import/ && NR > 1 {
        print imports imp
        printed = 1
      }
      { if (!printed && !/^import/) print imports; if (!/^import/) print }
      END { if (!printed) print imports imp }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
  
  # Replace axios.* with axiosInstance.*
  sed -i '' 's/\baxios\.get\b/axiosInstance.get/g' "$file"
  sed -i '' 's/\baxios\.post\b/axiosInstance.post/g' "$file"
  sed -i '' 's/\baxios\.put\b/axiosInstance.put/g' "$file"
  sed -i '' 's/\baxios\.delete\b/axiosInstance.delete/g' "$file"
  sed -i '' 's/\baxios\.patch\b/axiosInstance.patch/g' "$file"
  sed -i '' 's/\baxios\.request\b/axiosInstance.request/g' "$file"
  
  echo "  Replaced axios calls with axiosInstance"
done

echo "Done! All axios references have been updated."