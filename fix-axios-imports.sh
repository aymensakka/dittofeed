#!/bin/bash

# Find all files that import axios directly
files=$(find packages/dashboard/src -type f \( -name "*.ts" -o -name "*.tsx" \) -exec grep -l 'import.*axios from "axios"' {} \;)

for file in $files; do
  # Skip the axiosInstance.ts file itself
  if [[ "$file" == *"axiosInstance.ts" ]]; then
    continue
  fi
  
  echo "Updating $file"
  
  # Calculate the relative path from the file to axiosInstance.ts
  dir=$(dirname "$file")
  rel_path=$(python3 -c "import os.path; print(os.path.relpath('packages/dashboard/src/lib', '$dir'))")
  
  # Replace the import statement
  if [[ "$file" == *"/lib/"* ]]; then
    # Files in lib directory
    sed -i '' 's|import axios from "axios"|import axiosInstance from "./axiosInstance"|g' "$file"
  else
    # Files outside lib directory  
    sed -i '' "s|import axios from \"axios\"|import axiosInstance from \"$rel_path/axiosInstance\"|g" "$file"
  fi
  
  # Replace axios. with axiosInstance.
  sed -i '' 's/\baxios\./axiosInstance./g' "$file"
done

echo "Updated $(echo "$files" | wc -l) files"