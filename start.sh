#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./start.sh <repo_url> [target_dir] [branch] [--bg]
# Examples:
#   ./start.sh https://github.com/Ariyan20267/Vps.git
#   ./start.sh https://github.com/Ariyan20267/Vps.git mydir main --bg

REPO_URL="${1:-}"
if [ -z "$REPO_URL" ]; then
  echo "Error: repo_url is required."
  echo "Usage: $0 <repo_url> [target_dir] [branch] [--bg]"
  exit 2
fi

TARGET_DIR="${2:-}"
BRANCH="${3:-main}"
# If 4th argument is "--bg" OR 3rd is "--bg" when branch omitted
BG_FLAG=false
if [ "${4:-}" = "--bg" ] || [ "${3:-}" = "--bg" ]; then
  BG_FLAG=true
  # If branch was --bg and no branch provided, ensure BRANCH defaults to main
  if [ "${3:-}" = "--bg" ]; then
    BRANCH="main"
  fi
fi

# Derive default target dir from repo URL if not provided
if [ -z "$TARGET_DIR" ]; then
  # remove trailing .git and take last path component
  basename="$(basename -s .git "$REPO_URL")"
  TARGET_DIR="${basename}"
fi

echo "Repository: $REPO_URL"
echo "Target dir: $TARGET_DIR"
echo "Branch: $BRANCH"
echo "Background mode: $BG_FLAG"

# Determine whether to use sudo for package installs
USE_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    USE_SUDO="sudo"
  fi
fi

install_packages() {
  echo "Attempting to ensure git, python3, python3-venv, and pip are installed..."
  if command -v apt-get >/dev/null 2>&1; then
    $USE_SUDO apt-get update -y
    $USE_SUDO apt-get install -y git python3 python3-venv python3-pip || return 1
    return 0
  elif command -v yum >/dev/null 2>&1; then
    $USE_SUDO yum install -y git python3 python3-venv python3-pip || return 1
    return 0
  elif command -v apk >/dev/null 2>&1; then
    $USE_SUDO apk add --no-cache git python3 py3-virtualenv py3-pip || return 1
    return 0
  else
    echo "No supported package manager detected (apt-get, yum, apk). Skipping automatic package install."
    return 1
  fi
}

# Try best-effort to install packages (won't fail if package manager not present)
install_packages || true

# Ensure Git exists
if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed. Please install git and re-run this script."
  exit 3
fi

# Clone or update the repository
if [ -d "$TARGET_DIR/.git" ]; then
  echo "Repository already exists; updating..."
  cd "$TARGET_DIR"
  git fetch origin --depth=1 || true
  # Try to checkout branch; if missing, create tracking branch
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
  else
    git checkout -B "$BRANCH" "origin/$BRANCH" || git checkout -B "$BRANCH"
  fi
  git pull --ff-only origin "$BRANCH" || true
else
  echo "Cloning $REPO_URL into $TARGET_DIR..."
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

# Create a Python virtual environment if not present
VENV_DIR="venv"
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating virtual environment at ./$VENV_DIR..."
  if command -v python3 >/dev/null 2>&1; then
    python3 -m venv "$VENV_DIR"
  else
    python -m venv "$VENV_DIR"
  fi
fi

# Activate the virtual environment
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Upgrade pip and install requirements if file exists
echo "Upgrading pip..."
python -m pip install --upgrade pip setuptools wheel

if [ -f "requirements.txt" ]; then
  echo "Installing requirements from requirements.txt..."
  python -m pip install -r requirements.txt --no-cache-dir
else
  echo "No requirements.txt found. Skipping pip install -r requirements.txt."
fi

# If there's a setup script (optional), run it
if [ -f "setup.sh" ] && [ -x "setup.sh" ]; then
  echo "Running repository's setup.sh..."
  ./setup.sh
fi

# Final check: find main.py
if [ ! -f "main.py" ]; then
  echo "Error: main.py not found in repository root ($PWD)."
  echo "Listing files:"
  ls -la
  exit 4
fi

# Run main.py
if [ "$BG_FLAG" = true ]; then
  echo "Starting main.py in background (nohup). Logs -> run.log"
  nohup python main.py >> run.log 2>&1 &
  disown
  echo "Started. Check run.log for output."
else
  echo "Running main.py in foreground (use Ctrl+C to stop)..."
  exec python main.py
fi
