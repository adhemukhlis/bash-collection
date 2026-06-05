#!/bin/bash

# =============================================================================
# reset-repo.sh — Full repository reset script
#
# Resets a Git repository to a pristine state as if it was freshly created.
# The result is a single "main" branch with one "Initial commit" containing
# only .gitignore and README.md. All history, branches, and tags are purged.
# =============================================================================

set -euo pipefail

# --- Pre-flight checks -------------------------------------------------------

if [ ! -d ".git" ]; then
    echo "❌ Error: This directory is not a Git repository root!"
    exit 1
fi

# --- Configuration -----------------------------------------------------------

TARGET_BRANCH="main"
REPO_NAME=$(basename "$PWD")
SCRIPT_NAME=$(basename "$0")

# --- Confirmation prompt ------------------------------------------------------

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ⚠️  DESTRUCTIVE RESET — WARNING ⚠️              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  This will permanently:                                     ║"
echo "║                                                             ║"
echo "║  1. Delete ALL files except .gitignore and README.md        ║"
echo "║  2. Erase ALL commit history                                ║"
echo "║  3. Delete ALL local & remote branches (keep only main)     ║"
echo "║  4. Delete ALL local & remote tags                          ║"
echo "║  5. Reset README.md to contain only '# $REPO_NAME'"
echo "║  6. Create a single 'Initial commit' on branch 'main'      ║"
echo "║                                                             ║"
echo "║  THIS ACTION CANNOT BE UNDONE!                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Operation aborted."
    exit 0
fi

echo ""
echo "🔄 Initializing repository reset..."
echo ""

# --- Step 1: Back up .gitignore -----------------------------------------------

echo "[1/9] Backing up .gitignore..."
TEMP_GITIGNORE=$(mktemp)
if [ -f ".gitignore" ]; then
    cp .gitignore "$TEMP_GITIGNORE"
    echo "  ✓ .gitignore backed up"
else
    echo "  ⚠ No .gitignore found, skipping backup"
fi

# --- Step 2: Create orphan branch --------------------------------------------

echo "[2/9] Creating orphan branch..."
git checkout --orphan temp-reset-branch 2>/dev/null
echo "  ✓ Orphan branch created"

# --- Step 3: Clear Git index -------------------------------------------------

echo "[3/9] Clearing Git index..."
git read-tree --empty
echo "  ✓ Git index cleared"

# --- Step 4: Purge all files --------------------------------------------------

echo "[4/9] Purging all files..."
find . -maxdepth 1 ! -name '.' ! -name '.git' -exec rm -rf {}
echo "  ✓ All files purged"

# --- Step 5: Recreate core files ----------------------------------------------

echo "[5/9] Recreating core files..."
echo "# $REPO_NAME" >README.md
echo "  ✓ README.md created"

if [ -s "$TEMP_GITIGNORE" ]; then
    cp "$TEMP_GITIGNORE" .gitignore
    echo "  ✓ .gitignore restored from backup"
fi
rm -f "$TEMP_GITIGNORE"

# --- Step 6: Stage and commit -------------------------------------------------

echo "[6/9] Creating initial commit..."
git add .gitignore README.md 2>/dev/null
git add README.md
git commit -m "Initial commit" --quiet
echo "  ✓ Initial commit created"

# --- Step 7: Delete all local branches and rename to main ---------------------

echo "[7/9] Cleaning up local branches..."
for branch in $(git branch --format="%(refname:short)"); do
    if [ "$branch" != "temp-reset-branch" ]; then
        git branch -D "$branch" >/dev/null 2>&1 || true
        echo "  ✗ Deleted local branch: $branch"
    fi
done
git branch -m "$TARGET_BRANCH"
echo "  ✓ Renamed to '$TARGET_BRANCH'"

# --- Step 8: Delete all local tags -------------------------------------------

echo "[8/9] Cleaning up local tags..."
LOCAL_TAGS=$(git tag -l)
if [ -n "$LOCAL_TAGS" ]; then
    echo "$LOCAL_TAGS" | while read -r tag; do
        git tag -d "$tag" >/dev/null 2>&1 || true
        echo "  ✗ Deleted local tag: $tag"
    done
else
    echo "  ✓ No local tags found"
fi

# --- Step 9: Clean up Git internals ------------------------------------------

echo "[9/9] Cleaning up Git internals..."
git reflog expire --expire=now --all 2>/dev/null || true
git gc --prune=now --aggressive --quiet 2>/dev/null || true
echo "  ✓ Reflog expired and garbage collected"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Local repository successfully reset!"
echo "   Branch: $TARGET_BRANCH | Commits: 1 | Files: .gitignore, README.md"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# --- Remote sync (optional) ---------------------------------------------------

read -p "Do you want to sync reset to remote 'origin'? (y/N): " push_confirm
if [[ "$push_confirm" == "y" || "$push_confirm" == "Y" ]]; then
    echo ""

    # Check if remote origin exists
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo "❌ No remote 'origin' configured. Skipping remote sync."
    else
        # Force push main branch
        echo "  Pushing '$TARGET_BRANCH' to origin..."
        git push -f origin "$TARGET_BRANCH"
        echo "  ✓ Force push completed"

        # Set upstream
        git branch --set-upstream-to="origin/$TARGET_BRANCH" "$TARGET_BRANCH" >/dev/null 2>&1 || true

        # Fetch latest remote state
        git fetch origin --prune 2>/dev/null || true

        # Delete all other remote branches
        echo "  Cleaning remote branches..."
        for remote_branch in $(git branch -r --format="%(refname:short)"); do
            branch_name="${remote_branch#origin/}"
            if [ "$branch_name" != "$TARGET_BRANCH" ] && [ "$branch_name" != "HEAD" ]; then
                echo "  ✗ Deleting remote branch: $branch_name"
                git push origin --delete "$branch_name" 2>/dev/null || true
            fi
        done

        # Delete all remote tags
        echo "  Cleaning remote tags..."
        REMOTE_TAGS=$(git ls-remote --tags origin 2>/dev/null | awk '{print $2}' | sed 's|refs/tags/||' | sed 's|^{}||' | sort -u)
        if [ -n "$REMOTE_TAGS" ]; then
            echo "$REMOTE_TAGS" | while read -r tag; do
                echo "  ✗ Deleting remote tag: $tag"
                git push origin --delete "refs/tags/$tag" 2>/dev/null || true
            done
        else
            echo "  ✓ No remote tags found"
        fi

        echo ""
        echo "  ✅ Remote 'origin' synced successfully!"
    fi
else
    echo ""
    echo "Remote sync skipped. To push manually:"
    echo "  git push -f origin $TARGET_BRANCH"
fi

echo ""
echo "🎉 Repository reset complete. Clean slate achieved."
echo ""
