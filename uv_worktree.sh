#!/bin/bash
# 保存为 ~/.local/bin/uv-worktree

set -e

COMMAND=$1
BRANCH=$2

case $COMMAND in
    add)
        # 获取主仓库路径和项目名
        MAIN_REPO=$(git rev-parse --show-toplevel)
        PROJECT_NAME=$(basename "$MAIN_REPO")
        
        # 计算 worktrees 目录路径(与主仓库同级)
        WORKTREES_DIR="$(dirname "$MAIN_REPO")/${PROJECT_NAME}.worktrees"
        WORKTREE_PATH="$WORKTREES_DIR/$BRANCH"
        VENV_PATH="$MAIN_REPO/.venv"
        
        echo "📦 Creating worktree for branch: $BRANCH"
        
        # 创建 worktrees 目录(如果不存在)
        mkdir -p "$WORKTREES_DIR"
        
        # 创建 worktree
        if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
            # 分支已存在
            git worktree add "$WORKTREE_PATH" "$BRANCH"
        else
            # 创建新分支
            git worktree add -b "$BRANCH" "$WORKTREE_PATH"
        fi
        
        cd "$WORKTREE_PATH"
        
        # 链接虚拟环境
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
        
        # 同步依赖
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
        # 同步所有 worktree 的依赖
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
            
            # 检查是否有 .venv 链接
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
        DELETE_BRANCH=false
        # 解析选项
        while [[ "$2" == -* ]]; do
            case "$2" in
                -d|--branch)
                    DELETE_BRANCH=true
                    shift 2
                    ;;
                *)
                    echo "Error: Unknown option: $2"
                    echo "Usage: uv-worktree remove BRANCH [-d|--branch]"
                    exit 1
                    ;;
            esac
        done

        BRANCH_NAME=$2

        if [ -z "$BRANCH_NAME" ]; then
            echo "Error: Please specify branch name or worktree path"
            echo "Usage: uv-worktree remove BRANCH [-d|--branch]"
            exit 1
        fi
        
        MAIN_REPO=$(git rev-parse --show-toplevel)
        PROJECT_NAME=$(basename "$MAIN_REPO")
        WORKTREES_DIR="$(dirname "$MAIN_REPO")/${PROJECT_NAME}.worktrees"
        
        # 支持两种输入方式:分支名或完整路径
        if [ -d "$BRANCH_NAME" ]; then
            WORKTREE_PATH="$BRANCH_NAME"
        else
            WORKTREE_PATH="$WORKTREES_DIR/$BRANCH_NAME"
        fi
        
        if [ ! -d "$WORKTREE_PATH" ]; then
            echo "Error: Worktree not found: $WORKTREE_PATH"
            exit 1
        fi
        
        # 删除符号链接(如果存在)
        if [ -L "$WORKTREE_PATH/.venv" ]; then
            rm "$WORKTREE_PATH/.venv"
            echo "✓ Removed .venv symlink"
        fi
        
        # 删除 worktree
        git worktree remove "$WORKTREE_PATH" --force
        echo "✓ Worktree removed: $WORKTREE_PATH"

        # 可选:删除对应的 git 分支
        if [ "$DELETE_BRANCH" = true ]; then
            if git branch --list "$BRANCH_NAME" >/dev/null 2>&1; then
                git branch -d "$BRANCH_NAME"
                echo "✓ Branch deleted: $BRANCH_NAME"
            else
                echo "⚠ Branch not found locally: $BRANCH_NAME"
            fi
        fi
        
        # 如果 worktrees 目录为空,询问是否删除
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
        # 清理已删除的 worktree 引用
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
  remove BRANCH -d   Remove worktree and delete the branch
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

  # Remove worktree and delete the branch
  uv-worktree remove test -d

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
