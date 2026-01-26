# uv-worktree

A command-line tool for managing Git worktrees, designed specifically for Python projects using `uv`.

## Features

- **Automatic worktree creation**: Create independent worktrees in `<project>.worktrees/` directory
- **Shared virtual environment**: All worktrees share the main repository's `.venv`, saving disk space
- **Automatic dependency sync**: Automatically sync project dependencies when creating worktrees
- **Convenient management**: Provides add, sync, list, remove, prune commands

## Installation

```bash
# Download script
curl -o ~/.local/bin/uv-worktree https://raw.githubusercontent.com/yourusername/uv_worktree/main/uv_worktree.sh

# Add execute permission
chmod +x ~/.local/bin/uv-worktree

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### Create worktree

```bash
# Create worktree from existing branch
uv-worktree add feature-branch

# Create new branch and worktree
uv-worktree add new-feature
```

### Sync dependencies

```bash
# Sync dependencies in main repo, applies to all worktrees
uv-worktree sync
```

### List worktrees

```bash
# List all worktrees and their venv status
uv-worktree list
```

### Remove worktree

```bash
# Remove by branch name
uv-worktree remove feature-branch

# Remove by path
uv-worktree remove /path/to/project.worktrees/feature-branch
```

### Prune references

```bash
# Clean up stale worktree references
uv-worktree prune
```

## Directory Structure

```
/path/to/project/              (main repo)
/path/to/project.worktrees/
  ├── feature-branch/          (worktree for 'feature-branch')
  ├── bugfix/                  (worktree for 'bugfix' branch)
  └── experiment/              (worktree for 'experiment' branch)
```

## Requirements

- Git (with worktree support)
- [uv](https://github.com/astral-sh/uv) - Python package manager

## License

MIT License - see [LICENSE](LICENSE) file for details
