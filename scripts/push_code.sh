#!/bin/bash
set -e

# === PREVENT GIT FROM PROMPTING (hangs pty if token is wrong) ===
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo

# === ARGUMENTS ===
BRANCH_NAME="${1:-default-branch}"
REPO_NAME="$2"
GITHUB_USERNAME="$3"
ACCESS_TOKEN="$4"
GIT_EMAIL="$5"
GIT_NAME="$6"
# Optional 7th arg: when set, the script force-creates BRANCH at TARGET_HASH and
# pushes it directly — no `git add`/`git commit` so no concurrent file write
# can land on the deploy. Used by the rollback flow to guarantee the deployed
# commit is exactly the chat checkpoint, not whatever the working tree looks
# like at the moment of `git add`.
TARGET_HASH="${7:-}"

if [ -z "$REPO_NAME" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$ACCESS_TOKEN" ] || [ -z "$GIT_EMAIL" ] || [ -z "$GIT_NAME" ]; then
  echo "[git_push] ERROR: Missing arguments"
  echo "Usage: push_code.sh <branch_name> <repo_name> <github_username> <access_token> <git_email> <git_name> [target_hash]"
  exit 1
fi

echo "[git_push] Starting push to $REPO_NAME branch=$BRANCH_NAME owner=$GITHUB_USERNAME target_hash=$TARGET_HASH"

# === CONFIGURE GIT USER (REQUIRED FOR COMMIT) ===
git config --global user.email "$GIT_EMAIL"
git config --global user.name "$GIT_NAME"

# === CONSTRUCT REMOTE URL ===
REMOTE_URL="https://$GITHUB_USERNAME:$ACCESS_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME.git"

# === INIT REPO (handle fresh + re-push) ===
echo "[git_push] Initializing repo..."
if [ ! -d ".git" ]; then
  git init
else
  echo "[git_push] .git already exists, reusing"
fi

# === SET REMOTE (handle existing remote) ===
if git remote | grep -q origin; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

if [ -n "$TARGET_HASH" ]; then
  # === ROLLBACK MODE: force deploy branch to exactly TARGET_HASH and push it ===
  # Verify the hash exists locally before touching anything destructive.
  if ! git cat-file -e "$TARGET_HASH^{commit}" 2>/dev/null; then
    echo "[git_push] ERROR: target_hash $TARGET_HASH does not exist in this repo"
    exit 1
  fi
  # Force-create (or move) the deploy branch to point at the target commit.
  # `-B` resets the branch ref atomically and switches HEAD to it; the working
  # tree is updated to TARGET_HASH's content. No `git add`/`git commit` runs,
  # so any concurrent file write in the dir cannot land on the deploy.
  git checkout -B "$BRANCH_NAME" "$TARGET_HASH"
  COMMIT_HASH="$TARGET_HASH"
  echo "GIT_PUSH_COMMIT_HASH=$COMMIT_HASH"
  echo "[git_push] Pushing to origin/$BRANCH_NAME (rollback mode, TARGET_HASH=$TARGET_HASH) ..."
  git push -u origin "$BRANCH_NAME" --force
  echo "[git_push] SUCCESS: Pushed rollback branch '$BRANCH_NAME' at $TARGET_HASH to '$REPO_NAME'"
  exit 0
fi

# === CHECKOUT BRANCH (handle existing branch) ===
git checkout "$BRANCH_NAME" 2>/dev/null || git checkout -b "$BRANCH_NAME"

# === STAGE AND COMMIT ===
git add .
if git diff --cached --quiet 2>/dev/null; then
  echo "[git_push] No new changes to commit, pushing existing"
else
  git commit -m "Initial commit on $BRANCH_NAME"
fi
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
echo "GIT_PUSH_COMMIT_HASH=$COMMIT_HASH"

# === PUSH (force to keep local as source of truth) ===
echo "[git_push] Pushing to origin/$BRANCH_NAME ..."
git push -u origin "$BRANCH_NAME" --force

echo "[git_push] SUCCESS: Pushed branch '$BRANCH_NAME' to '$REPO_NAME'"
