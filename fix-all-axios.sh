#!/bin/bash

echo "Finding all files using axios directly..."

# Find all TypeScript/TSX files that use axios but don't import it
files=$(grep -r "axios\." /Users/aymensakka/dittofeed-multitenant/packages/dashboard/src \
  --include="*.ts" --include="*.tsx" \
  | grep -v "axiosInstance" \
  | grep -v "// " \
  | cut -d: -f1 \
  | sort -u)

for file in $files; do
  # Check if file imports axios
  if grep -q "^import.*axios.*from.*['\"]axios['\"]" "$file"; then
    echo "Fixing imports in $file"
    # Replace axios import with axiosInstance import
    
    # Get directory relative path for import
    dir=$(dirname "$file")
    rel_path=$(python3 -c "import os.path; print(os.path.relpath('/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib', '$dir'))")
    
    # Replace import statement
    if [[ "$file" == *"/lib/"* ]]; then
      # Files in lib directory
      sed -i '' 's|^import axios from "axios"|import axiosInstance from "./axiosInstance"|g' "$file"
      sed -i '' 's|^import axios, |import axiosInstance, |g' "$file"
      sed -i '' 's|^import { |import axiosInstance from "./axiosInstance";\nimport { |' "$file"
    else
      # Files outside lib directory  
      sed -i '' "s|^import axios from \"axios\"|import axiosInstance from \"$rel_path/axiosInstance\"|g" "$file"
      sed -i '' "s|^import axios, |import axiosInstance, |g" "$file"
    fi
  else
    # File uses axios but doesn't import it - add the import
    echo "Adding import to $file"
    dir=$(dirname "$file")
    rel_path=$(python3 -c "import os.path; print(os.path.relpath('/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib', '$dir'))")
    
    # Add import at the beginning of the file after the first import
    if [[ "$file" == *"/lib/"* ]]; then
      sed -i '' '1a\
import axiosInstance from "./axiosInstance";
' "$file"
    else
      sed -i '' "1a\\
import axiosInstance from \"$rel_path/axiosInstance\";
" "$file"
    fi
  fi
  
  # Replace axios. with axiosInstance.
  sed -i '' 's/\baxios\./axiosInstance./g' "$file"
done

echo "Fixed $(echo "$files" | wc -l) files"