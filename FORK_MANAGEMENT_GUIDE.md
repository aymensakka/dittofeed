# Fork Management Guide for Dittofeed Multi-Tenant

## Overview
This guide explains how to maintain your multi-tenant fork while incorporating updates from the upstream Dittofeed repository.

## Key Features Added in This Fork

### 1. Multi-Tenancy Support
- Workspace-based isolation with Parent/Child hierarchy
- Tenant-specific quotas and metrics
- OAuth integration (Google, HubSpot)
- Row-level security for all database tables

### 2. Embedded Dashboard
- **NEW**: Iframe-embeddable dashboard components
- Secure session management with JWT tokens
- Refresh token mechanism for long-lived sessions
- Components available for embedding:
  - Journey Builder
  - Broadcast Manager
  - Segment Editor
  - Template Editor
  - Delivery Analytics

### 3. Enhanced Security
- JWT-based authentication with refresh tokens
- Token rotation and reuse detection
- Session auditing and rate limiting
- Workspace-scoped API access

---

## Initial Setup (One-time)

### 1. Add Upstream Remote
```bash
# Add the original Dittofeed repository as "upstream"
git remote add upstream https://github.com/dittofeed/dittofeed.git

# Verify remotes
git remote -v
# You should see:
# origin    https://github.com/aymensakka/dittofeed.git (fetch)
# origin    https://github.com/aymensakka/dittofeed.git (push)
# upstream  https://github.com/dittofeed/dittofeed.git (fetch)
# upstream  https://github.com/dittofeed/dittofeed.git (push)
```

### 2. Create Feature Branches
```bash
# Create a branch for your multi-tenant features
git checkout -b multi-tenant-main

# Keep main branch for syncing with upstream
git checkout main
```

---

## Regular Sync Process

### Step 1: Fetch Upstream Changes
```bash
# Fetch all branches from upstream
git fetch upstream

# View all branches
git branch -a
```

### Step 2: Merge Upstream Changes to Main
```bash
# Switch to your main branch
git checkout main

# Merge upstream changes
git merge upstream/main

# Push to your fork
git push origin main
```

### Step 3: Integrate Changes to Your Feature Branch
```bash
# Switch to your multi-tenant branch
git checkout multi-tenant-main

# Merge or rebase from main
# Option A: Merge (preserves history)
git merge main

# Option B: Rebase (cleaner history)
git rebase main

# Resolve any conflicts
# Push your branch
git push origin multi-tenant-main
```

---

## Conflict Resolution Strategy

### Common Conflict Areas

1. **Database Schema (`packages/backend-lib/src/db/schema.ts`)**
   - Your changes: Multi-tenancy fields, RLS policies
   - Resolution: Keep both, ensure compatibility

2. **API Routes (`packages/api/src/`)**
   - Your changes: Workspace context, JWT auth
   - Resolution: Integrate new endpoints with auth middleware

3. **Frontend Components (`packages/dashboard/src/`)**
   - Your changes: Axios interceptors, workspace context
   - Resolution: Apply your auth logic to new components

### Conflict Resolution Process

```bash
# When conflicts occur during merge
git status  # See conflicted files

# For each conflicted file
# 1. Open in editor
# 2. Look for conflict markers: <<<<<<<, =======, >>>>>>>
# 3. Resolve manually, keeping both functionalities

# Example resolution pattern:
# <<<<<<< HEAD (your changes)
#   // Your multi-tenant code
# =======
#   // Upstream new feature
# >>>>>>> upstream/main

# After resolution
git add <resolved-file>
git commit -m "Merge upstream: resolved conflicts in [describe areas]"
```

---

## Best Practices

### 1. Modularize Your Changes
Create separate files where possible:
```
packages/backend-lib/src/multitenancy/   # Your multi-tenant logic
packages/dashboard/src/lib/multiTenant/  # Frontend multi-tenant utilities
```

### 2. Use Feature Flags
```typescript
// config.ts
export const FEATURES = {
  MULTI_TENANCY: process.env.ENABLE_MULTI_TENANCY === 'true',
  OAUTH_AUTH: process.env.ENABLE_OAUTH === 'true',
};

// In code
if (FEATURES.MULTI_TENANCY) {
  // Your multi-tenant logic
}
```

### 3. Document Your Changes
Maintain a changelog of your modifications:
```markdown
# MULTI_TENANT_CHANGES.md

## Database Changes
- Added workspaceId to all tables
- Added RLS policies
- Created workspaceOccupantSettings table

## API Changes
- Added JWT authentication
- Added workspace context middleware
- Modified all endpoints for workspace scoping

## Frontend Changes
- Added axios interceptors
- Added workspace selector
- Modified all API calls to include workspace context
```

### 4. Test After Each Merge
```bash
# Run tests after merging upstream
yarn test

# Run your multi-tenant specific tests
yarn test:multitenancy

# Run E2E tests
npx playwright test
```

---

## Automated Sync Script

Create a script to automate the sync process:

```bash
#!/bin/bash
# sync-upstream.sh

echo "🔄 Syncing with upstream Dittofeed..."

# Fetch upstream
git fetch upstream

# Backup current branch
current_branch=$(git branch --show-current)
git branch backup-$current_branch-$(date +%Y%m%d)

# Update main
git checkout main
git merge upstream/main --no-edit

# Update multi-tenant branch
git checkout multi-tenant-main
echo "📝 Attempting to merge main into multi-tenant-main..."
git merge main --no-edit

if [ $? -ne 0 ]; then
    echo "⚠️  Conflicts detected! Please resolve manually."
    echo "Conflicted files:"
    git diff --name-only --diff-filter=U
else
    echo "✅ Merge successful!"
    git push origin main
    git push origin multi-tenant-main
fi

git checkout $current_branch
```

---

## Version Tagging Strategy

```bash
# Tag your multi-tenant versions
git tag -a v1.0.0-mt -m "Multi-tenant v1.0.0 based on upstream v1.0.0"

# When upstream releases new version
git fetch upstream --tags
git tag -a v1.1.0-mt -m "Multi-tenant v1.1.0 merged with upstream v1.1.0"
```

---

## CI/CD Considerations

### GitHub Actions Workflow
```yaml
# .github/workflows/sync-upstream.yml
name: Sync with Upstream

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  workflow_dispatch:  # Manual trigger

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
          
      - name: Sync upstream
        run: |
          git config user.name 'GitHub Action'
          git config user.email 'action@github.com'
          git remote add upstream https://github.com/dittofeed/dittofeed.git
          git fetch upstream
          git checkout main
          git merge upstream/main --no-edit
          git push origin main
          
      - name: Create PR for multi-tenant merge
        uses: peter-evans/create-pull-request@v5
        with:
          branch: auto-sync-upstream
          title: 'Auto-sync: Merge upstream changes'
          body: 'Automated sync with upstream Dittofeed repository'
```

---

## Handling Breaking Changes

### Migration Strategy
When upstream introduces breaking changes:

1. **Review Release Notes**
   ```bash
   # Check upstream releases
   open https://github.com/dittofeed/dittofeed/releases
   ```

2. **Test in Isolation**
   ```bash
   # Create test branch
   git checkout -b test-upstream-merge
   git merge upstream/main
   
   # Run full test suite
   yarn test
   npx playwright test
   ```

3. **Update Your Code**
   - Adapt multi-tenant features to new APIs
   - Update database migrations if schema changed
   - Modify tests for new behavior

4. **Document Changes**
   ```markdown
   # BREAKING_CHANGES_LOG.md
   
   ## [Date] Upstream Version X.X.X
   ### Changes Required:
   - Updated API authentication to work with new middleware
   - Modified database migrations for new schema
   - Adapted frontend components to new prop structure
   ```

---

## Rollback Plan

If merge causes critical issues:

```bash
# Rollback to previous state
git checkout multi-tenant-main
git reset --hard backup-multi-tenant-main-[date]

# Or revert specific merge
git revert -m 1 [merge-commit-hash]
```

---

## Contributing Back

Consider contributing general improvements back to upstream:

1. **Identify Shareable Features**
   - Bug fixes
   - Performance improvements
   - General features (not multi-tenant specific)

2. **Create Clean PR**
   ```bash
   # Create branch from upstream main
   git checkout -b feature-for-upstream upstream/main
   
   # Cherry-pick specific commits
   git cherry-pick [commit-hash]
   
   # Push and create PR
   git push origin feature-for-upstream
   ```

3. **Follow Upstream Guidelines**
   - Read CONTRIBUTING.md
   - Follow code style
   - Include tests
   - Update documentation

---

## Monitoring Upstream

### Stay Informed
- Watch upstream repository for releases
- Subscribe to discussions/issues
- Join Discord/Slack community

### Track Important Changes
```bash
# Check what changed between versions
git diff v1.0.0 v1.1.0 --stat

# See specific file changes
git diff v1.0.0 v1.1.0 -- packages/backend-lib/src/db/schema.ts
```

---

## Emergency Contacts

- **Upstream Issues**: https://github.com/dittofeed/dittofeed/issues
- **Your Fork Issues**: https://github.com/aymensakka/dittofeed/issues
- **Documentation**: https://docs.dittofeed.com

---

## Checklist for Each Sync

- [ ] Backup current branches
- [ ] Fetch upstream changes
- [ ] Review upstream changelog/release notes
- [ ] Merge to main branch
- [ ] Test main branch
- [ ] Merge to multi-tenant branch
- [ ] Resolve conflicts
- [ ] Run all tests
- [ ] Update documentation
- [ ] Tag new version
- [ ] Deploy to staging
- [ ] Verify functionality
- [ ] Deploy to production

---

*Last Updated: 2025-08-23*
*Maintained by: Multi-Tenant Team*