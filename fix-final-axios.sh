#!/bin/bash

# Fix all remaining axios references in dashboard
FILES=(
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/usePermissionsMutations.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useOauthSetCsrfMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDownloadSegmentsMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDownloadEventsMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDownloadDeliveriesMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteUserPropertyMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteUserMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteSubscriptionGroupMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteSegmentMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteMessageTemplateMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useDeleteJourneyMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useUsersCountQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useUserPropertiesQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useTriggerRecomputePropertiesMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useTraitsQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useStartBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useResumeBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useRenderTemplateQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useRecomputeBroadcastSegmentMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/usePropertiesQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/usePauseBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useMessageTemplateUpdateMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useJourneyStats.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useJourneyMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useGmailAuthorizationQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useEventsQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useCreateSubscriptionGroupMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useCreateJourneyMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useCreateBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useCancelBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useBroadcastsQuery.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/useArchiveBroadcastMutation.ts"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/pages/settings.page.tsx"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/components/deliveriesTableV2.tsx"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/components/deliveriesTable.tsx"
  "/Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/components/eventsTable.tsx"
)

for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "Processing $file..."
    
    # Check if file already imports axiosInstance
    if ! grep -q 'import.*axiosInstance.*from.*["\047]\.\/axiosInstance["\047]' "$file"; then
      # Add axiosInstance import after the last import statement if not present
      sed -i '' '/^import.*from/h;$!d;x;s/.*/&\nimport axiosInstance from ".\/axiosInstance";/' "$file"
    fi
    
    # Replace axios.get, axios.post, etc. with axiosInstance
    sed -i '' 's/\baxios\.get\b/axiosInstance.get/g' "$file"
    sed -i '' 's/\baxios\.post\b/axiosInstance.post/g' "$file"
    sed -i '' 's/\baxios\.put\b/axiosInstance.put/g' "$file"
    sed -i '' 's/\baxios\.delete\b/axiosInstance.delete/g' "$file"
    sed -i '' 's/\baxios\.patch\b/axiosInstance.patch/g' "$file"
    sed -i '' 's/\baxios\.request\b/axiosInstance.request/g' "$file"
  fi
done

echo "Completed fixing axios references"