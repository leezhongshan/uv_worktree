#!/bin/bash
# Save as ~/.local/bin/uv-worktree

set -e

COMMAND=$1
BRANCH=$2

case $COMMAND in
    add)
        # Get main repo path and project name
        MAIN_REPO=$(git rev-parse --show-toplevel)
        PROJECT_NAME=$(basename "$MAIN_REPO")

        # Calculate worktrees directory path (at same level as main repo)
        WORKTREES_DIR="$(dirname "$MAIN_REPO")/${PROJECT_NAME}.worktrees"
        WORKTREE_PATH="$WORKTREES_DIR/$BRANCH"
        VENV_PATH="$MAIN_REPO/.venv"

        echo "📦 Creating worktree for branch: $BRANCH"

        # Create worktrees directory (if not exists)
        mkdir -p "$WORKTREES_DIR"

        # Create worktree
        if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
            # Branch already exists
            git worktree add "$WORKTREE_PATH" "$BRANCH"
        else
            # Create new branch
            git worktree add -b "$BRANCH" "$WORKTREE_PATH"
        fi

        cd "$WORKTREE_PATH"

        # Link virtual environment
        if [ -d "$VENV_PATH" ]; then
            ln -sf "$VENV_PATH" .venv
            echo "✓ Linked shared .venv from main repo"
        else
            echo "⚠ No .venv in main repo, creating new one..."
            cd "$MAIN_REPO"
            uv venv
            cd "$WORKTREE_PATH"
            ln -sf "$VENV_PATH" .venv
        fi

        # Sync dependencies
        if [ -f "$MAIN_REPO/pyproject.toml" ]; then
            echo "📥 Syncing dependencies with uv..."
            uv sync 2>/dev/null || echo "⚠ uv sync failed, trying pip install..."
        elif [ -f "$MAIN_REPO/requirements.txt" ]; then
            echo "📥 Installing dependencies..."
            uv pip install -r "$MAIN_REPO/requirements.txt" 2>/dev/null || true
        fi
        
        echo "✓ Worktree ready at: $WORKTREE_PATH"
        echo ""
        echo "To switch to this worktree:"
        echo "  cd $WORKTREE_PATH"
        ;;
        
    sync)
        # Sync dependencies for all worktrees
        MAIN_REPO=$(git rev-parse --show-toplevel)
        cd "$MAIN_REPO"

        echo "📥 Syncing dependencies in main repo..."
        if [ -f "pyproject.toml" ]; then
            uv sync
        elif [ -f "requirements.txt" ]; then
            uv pip install -r requirements.txt
        else
            echo "⚠ No pyproject.toml or requirements.txt found"
            exit 1
        fi
        
        PROJECT_NAME=$(basename "$MAIN_REPO")
        WORKTREES_DIR="$(dirname "$MAIN_REPO")/${PROJECT_NAME}.worktrees"
        
        if [ -d "$WORKTREES_DIR" ]; then
            echo "✓ Dependencies synced for all worktrees using shared .venv"
        fi
        ;;
        
    list)
        MAIN_REPO=$(git rev-parse --show-toplevel)
        PROJECT_NAME=$(basename "$MAIN_REPO")

        echo "Main repository:"
        echo "  $MAIN_REPO"
        echo ""
        echo "Worktrees:"

        git worktree list | tail -n +2 | while IFS= read -r line; do
            WORKTREE=$(echo "$line" | awk '{print $1}')
            BRANCH=$(echo "$line" | awk '{print $3}' | tr -d '[]')

            # Check if .venv is linked
            if [ -L "$WORKTREE/.venv" ]; then
                VENV_STATUS="✓ .venv linked"
            elif [ -d "$WORKTREE/.venv" ]; then
                VENV_STATUS="⚠ .venv exists (not linked)"
            else
                VENV_STATUS="✗ no .venv"
            fi

            echo "  $WORKTREE [$BRANCH] - $VENV_STATUS"
        done
        ;;
        
    remove|rm)
        if [ -z "$BRANCH" ]; then
            echo "Error: Please specify branch name or worktree path"
            exit 1
        fi

        MAIN_REPO=$(git rev-parse --show-toplevel)
        PROJECT_NAME=$(basename "$MAIN_REPO")
        WORKTREES_DIR="$(dirname "$MAIN_REPO")/${PROJECT_NAME}.worktrees"

        # Support two input methods: branch name or full path
        if [ -d "$BRANCH" ]; then
            WORKTREE_PATH="$BRANCH"
        else
            WORKTREE_PATH="$WORKTREES_DIR/$BRANCH"
        fi

        if [ ! -d "$WORKTREE_PATH" ]; then
            echo "Error: Worktree not found: $WORKTREE_PATH"
            exit 1
        fi

        # Remove symbolic link (if exists)
        if [ -L "$WORKTREE_PATH/.venv" ]; then
            rm "$WORKTREE_PATH/.venv"
            echo "✓ Removed .venv symlink"
        fi

        # Remove worktree
        git worktree remove "$WORKTREE_PATH"
        echo "✓ Worktree removed: $WORKTREE_PATH"

        # If worktrees directory is empty, ask to remove it
        if [ -d "$WORKTREES_DIR" ] && [ -z "$(ls -A "$WORKTREES_DIR")" ]; then
            echo ""
            echo "The worktrees directory is now empty."
            read -p "Remove $WORKTREES_DIR? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rmdir "$WORKTREES_DIR"
                echo "✓ Removed empty worktrees directory"
            fi
        fi
        ;;

    prune)
        # Clean up stale worktree references
        git worktree prune
        echo "✓ Pruned stale worktree references"
        ;;
        
    *)
        cat << 'USAGE'
Usage: uv-worktree COMMAND [OPTIONS]

Commands:
  add BRANCH           Create worktree at <project>.worktrees/BRANCH
  sync                 Sync dependencies across all worktrees
  list                 List all worktrees with venv status
  remove BRANCH        Remove worktree by branch name
  prune                Prune stale worktree references

Examples:
  # Create worktree (creates uv_worktree.worktrees/test/)
  uv-worktree add test

  # Sync dependencies to all worktrees
  uv-worktree sync

  # List all worktrees
  uv-worktree list

  # Remove worktree
  uv-worktree remove test

  # Cleanup stale references
  uv-worktree prune

Directory structure:
  /path/to/uv_worktree/              (main repo)
  /path/to/uv_worktree.worktrees/
    ├── test/                        (worktree for 'test' branch)
    ├── feature-x/                   (worktree for 'feature-x' branch)
    └── bugfix-y/                    (worktree for 'bugfix-y' branch)
USAGE
        exit 1
        ;;
esac