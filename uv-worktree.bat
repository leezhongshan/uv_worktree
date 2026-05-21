@echo off
setlocal enabledelayedexpansion

:: uv-worktree.bat - Windows compatible worktree manager
:: Requires: Git and uv installed and in PATH
:: Save as: C:\path\to\uv-worktree.bat (or put in PATH)

set "COMMAND=%~1"
set "BRANCH=%~2"

if "%COMMAND%"=="" goto usage

:: ---------- add ----------
if "%COMMAND%"=="add" (
    call :main_repo
    call :project_name "!MAIN_REPO!"

    set "WORKTREES_DIR=%~dp0%PROJECT_NAME%.worktrees"
    set "WORKTREE_PATH=%WORKTREES_DIR%\%BRANCH%"
    set "VENV_PATH=%MAIN_REPO%\.venv"

    :: Create worktrees directory
    if not exist "%WORKTREES_DIR%\" mkdir "%WORKTREES_DIR%"

    :: Check if branch exists
    git rev-parse --verify "%BRANCH%" >nul 2>&1
    if !errorlevel! equ 0 (
        git worktree add "!WORKTREE_PATH!" "%BRANCH%"
    ) else (
        git worktree add -b "%BRANCH%" "!WORKTREE_PATH!"
    )

    :: Link or create venv
    if exist "%VENV_PATH%\" (
        call :mklink_junction "!WORKTREE_PATH!\.venv" "%VENV_PATH%"
        echo [OK] Linked shared .venv from main repo
    ) else (
        echo [WARN] No .venv in main repo, creating...
        pushd "%MAIN_REPO%"
        uv venv
        popd
        call :mklink_junction "!WORKTREE_PATH!\.venv" "%VENV_PATH%"
    )

    :: Sync dependencies
    if exist "%MAIN_REPO%\pyproject.toml" (
        pushd "!WORKTREE_PATH!"
        uv sync
        popd
    ) else if exist "%MAIN_REPO%\requirements.txt" (
        uv pip install -r "%MAIN_REPO%\requirements.txt"
    )

    echo [OK] Worktree ready at: !WORKTREE_PATH!
    echo.
    echo To switch to this worktree:
    echo   cd /d !WORKTREE_PATH!
    goto :end
)

:: ---------- sync ----------
if "%COMMAND%"=="sync" (
    call :main_repo
    pushd "%MAIN_REPO%"

    if exist "pyproject.toml" (
        uv sync
    ) else if exist "requirements.txt" (
        uv pip install -r requirements.txt
    ) else (
        echo [ERROR] No pyproject.toml or requirements.txt found
        exit /b 1
    )

    popd
    call :project_name "%MAIN_REPO%"
    set "WORKTREES_DIR=%~dp0%PROJECT_NAME%.worktrees"
    if exist "%WORKTREES_DIR%\" (
        echo [OK] Dependencies synced for all worktrees using shared .venv
    )
    goto :end
)

:: ---------- list ----------
if "%COMMAND%"=="list" (
    call :main_repo
    call :project_name "!MAIN_REPO!"

    echo Main repository:
    echo   !MAIN_REPO!
    echo.
    echo Worktrees:

    for /f "tokens=1,3" %%a in ('git worktree list ^| more +1') do (
        set "WT_PATH=%%a"
        set "WT_BRANCH=%%b"
        set "WT_BRANCH=!WT_BRANCH:[=!"
        set "WT_BRANCH=!WT_BRANCH:]=!"

        :: check .venv link
        if exist "!WT_PATH!\.venv\" (
            set "VENV_STATUS=[OK] .venv linked"
        ) else if exist "!WT_PATH!\.venv" (
            set "VENV_STATUS=[WARN] .venv exists (not linked)"
        ) else (
            set "VENV_STATUS=[FAIL] no .venv"
        )

        echo   !WT_PATH! [!WT_BRANCH!] - !VENV_STATUS!
    )
    goto :end
)

:: ---------- remove / rm ----------
if "%COMMAND%"=="remove" goto remove
if "%COMMAND%"=="rm" goto remove
goto :usage_end

:remove
    set "DELETE_BRANCH=false"
    set "TARGET=%~2"

    :: parse options
    :remove_opt_loop
    if "%~2"=="" goto remove_done_opts
    if "%~2"=="-d" (
        set "DELETE_BRANCH=true"
        shift
        goto remove_opt_loop
    )
    if "%~2"=="--branch" (
        set "DELETE_BRANCH=true"
        shift
        goto remove_opt_loop
    )
    shift
    goto remove_opt_loop

    :remove_done_opts
    set "TARGET=%~2"

    if "!TARGET!"=="" (
        echo [ERROR] Please specify branch name or worktree path
        echo Usage: uv-worktree remove BRANCH [-d^|--branch]
        exit /b 1
    )

    call :main_repo
    call :project_name "!MAIN_REPO!"
    set "WORKTREES_DIR=%~dp0%PROJECT_NAME%.worktrees"

    :: support both branch name and full path
    if exist "!TARGET!\*" (
        set "WORKTREE_PATH=!TARGET!"
    ) else (
        set "WORKTREE_PATH=%WORKTREES_DIR%\!TARGET!"
    )

    if not exist "!WORKTREE_PATH!\*" (
        echo [ERROR] Worktree not found: !WORKTREE_PATH!
        exit /b 1
    )

    :: remove .venv link (junction)
    if exist "!WORKTREE_PATH!\.venv\" (
        rmdir "!WORKTREE_PATH!\.venv" 2>nul
        if exist "!WORKTREE_PATH!\.venv" (
            :: might be a regular directory (non-junction)
            rmdir /s /q "!WORKTREE_PATH!\.venv" 2>nul
        )
        echo [OK] Removed .venv link
    )

    :: remove worktree
    git worktree remove "!WORKTREE_PATH!" --force
    echo [OK] Worktree removed: !WORKTREE_PATH!

    :: optionally delete branch
    if "!DELETE_BRANCH!"=="true" (
        git branch --list "!TARGET!" >nul 2>&1
        if !errorlevel! equ 0 (
            git branch -d "!TARGET!"
            echo [OK] Branch deleted: !TARGET!
        ) else (
            echo [WARN] Branch not found locally: !TARGET!
        )
    )

    goto :end

:: ---------- prune ----------
if "%COMMAND%"=="prune" (
    git worktree prune
    echo [OK] Pruned stale worktree references
    goto :end
)

:: ---------- usage ----------
:usage
echo Usage: uv-worktree COMMAND [OPTIONS]
echo.
echo Commands:
echo   add BRANCH          Create worktree at ^<project^>.worktrees\BRANCH
echo   sync                Sync dependencies across all worktrees
echo   list                List all worktrees with venv status
echo   remove BRANCH       Remove worktree by branch name
echo   remove BRANCH -d    Remove worktree and delete the branch
echo   prune               Prune stale worktree references
echo.
echo Examples:
echo   uv-worktree add test
echo   uv-worktree sync
echo   uv-worktree list
echo   uv-worktree remove test
echo   uv-worktree remove test -d
echo   uv-worktree prune
echo.
echo Directory structure:
echo   C:\path\to\uv_worktree\              (main repo)
echo   C:\path\to\uv_worktree.worktrees\
echo     test\                            (worktree for 'test' branch)
echo     feature-x\                       (worktree for 'feature-x' branch)
echo     bugfix-y\                        (worktree for 'bugfix-y' branch)
:usage_end
exit /b 1

:: ---------- helpers ----------

:main_repo
    for /f "delims=" %%r in ('git rev-parse --show-toplevel') do set "MAIN_REPO=%%r"
    exit /b 0

:project_name
    set "REPO_PATH=%~1"
    for %%p in (!REPO_PATH!) do set "PROJECT_NAME=%%~nxp"
    exit /b 0

:: Create a directory junction on Windows (requires admin/developer mode)
:: Falls back to copying .venv if mklink fails
:mklink_junction
    set "LINK=%~1"
    set "TARGET=%~2"
    :: Try junction first (doesn't need admin)
    mklink /J "!LINK!" "!TARGET!" >nul 2>&1
    if errorlevel 1 (
        :: Junction failed (probably no admin rights)
        :: Fallback: xcopy the venv (read-only copy)
        xcopy /E /I /H /Y "!TARGET!" "!LINK!" >nul 2>&1
    )
    exit /b 0

:end
endlocal
