# Switching to Dev Branch on VPS

## First Time Setup (if you haven't pulled latest changes)

```bash
# Navigate to your termiNAS directory
cd /opt/terminas  # or wherever you cloned it

# Fetch all branches from GitHub
git fetch origin

# List all available branches (verify dev exists)
git branch -a

# Switch to dev branch
git checkout dev

# Verify you're on dev branch
git branch
```

## If Already Have a Local Copy

```bash
# Navigate to termiNAS directory
cd /opt/terminas

# Ensure you're starting clean (no uncommitted changes)
git status

# Fetch latest changes
git fetch origin

# Switch to dev branch
git checkout dev

# Pull latest changes
git pull origin dev

# Verify you're on correct branch and up to date
git branch
git log --oneline -5
```

## Quick One-Liner

```bash
cd /opt/terminas && git fetch origin && git checkout dev && git pull origin dev
```

## Verify You're on Dev Branch

```bash
# Check current branch (should show * dev)
git branch

# Or check with more detail
git status
```

## Common Issues

### Issue: "error: Your local changes would be overwritten"

If you have local modifications:

```bash
# Option 1: Save changes to a new branch
git stash
git checkout dev
git stash pop

# Option 2: Discard local changes (⚠️ BE CAREFUL)
git reset --hard HEAD
git checkout dev
```

### Issue: Branch doesn't exist

If `dev` branch doesn't show up:

```bash
# Make sure you fetched from GitHub first
git fetch origin

# Then try checkout
git checkout dev
```

### Issue: Need to stay on main for production

If you want `main` for production and `dev` for testing:

```bash
# Keep production on main
cd /opt/terminas-production
git checkout main
git pull origin main

# Use dev for testing in separate directory
cd /opt/terminas-dev
git checkout dev
git pull origin dev
```

## Switching Back to Main

```bash
cd /opt/terminas
git checkout main
git pull origin main
```

## Keeping Updated

To get latest changes from dev branch:

```bash
cd /opt/terminas
git pull origin dev
```

---

**Remember:** 
- `main` = stable releases only
- `dev` = latest development (may have new features)
