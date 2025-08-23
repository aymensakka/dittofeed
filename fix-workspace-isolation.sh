#!/bin/bash

echo "Checking for workspace isolation issues in database queries..."

# Find all queries that might be missing workspace filters
echo "Potential issues found:"

# Check for subscriptionGroup queries without workspace filter
echo ""
echo "=== Subscription Group Queries ==="
grep -rn "subscriptionGroup.findFirst\|subscriptionGroup.findMany" packages/ --include="*.ts" --include="*.tsx" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    # Check if the next few lines contain workspaceId
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "WARNING: $line"
        echo "  ^ May be missing workspace filter"
    fi
done

# Check for segment queries without workspace filter
echo ""
echo "=== Segment Queries ==="
grep -rn "segment.findFirst\|segment.findMany" packages/ --include="*.ts" --include="*.tsx" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "WARNING: $line"
        echo "  ^ May be missing workspace filter"
    fi
done

# Check for journey queries without workspace filter  
echo ""
echo "=== Journey Queries ==="
grep -rn "journey.findFirst\|journey.findMany" packages/ --include="*.ts" --include="*.tsx" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "WARNING: $line"
        echo "  ^ May be missing workspace filter"
    fi
done

# Check for messageTemplate queries without workspace filter
echo ""
echo "=== Message Template Queries ==="
grep -rn "messageTemplate.findFirst\|messageTemplate.findMany" packages/ --include="*.ts" --include="*.tsx" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "WARNING: $line"
        echo "  ^ May be missing workspace filter"
    fi
done

echo ""
echo "=== API Delete Operations ==="
# Check for delete operations without workspace filter
grep -rn "\.delete(schema\." packages/api/src/controllers/ --include="*.ts" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+10))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "WARNING: $line"
        echo "  ^ Delete operation may be missing workspace filter"
    fi
done

echo ""
echo "Check complete. Review the warnings above for potential workspace isolation issues."