@echo off
REM Qwen Code Docker Startup Script (Windows Batch)
REM Handles container states, rebuilds, and data persistence

setlocal enabledelayedexpansion

REM Check for --rebuild flag
set FORCE_REBUILD=false
if "%1"=="--rebuild" set FORCE_REBUILD=true
if "%1"=="-r" set FORCE_REBUILD=true
if "%FORCE_REBUILD%"=="true" echo [INFO] Force rebuild requested

echo [INFO] Starting Qwen Code Docker Environment...

REM Check if .env exists, run setup if not
if not exist ".env" (
    echo [WARNING] .env file not found. Please create one manually or run the setup wizard
    echo [ERROR] Create a .env file with your configuration
    exit /b 1
)

REM Clear any potentially conflicting environment variables
echo [INFO] Clearing conflicting environment variables...
set OPENAI_API_KEY=
set OPENAI_BASE_URL=
set OPENAI_MODEL=
set GEMINI_DEFAULT_AUTH_TYPE=
set USE_GEMINI_BRIDGE=
set BRIDGE_TARGET_URL=
set BRIDGE_PORT=
set BRIDGE_DEBUG=

REM Load .env file (basic implementation for Windows)
echo [INFO] Loading environment from .env file...
for /f "usebackq tokens=1,2 delims==" %%i in (".env") do (
    if not "%%i"=="" if not "%%i:~0,1%"=="#" set %%i=%%j
)

REM Set default environment variables
if not defined OPENAI_BASE_URL set OPENAI_BASE_URL=http://localhost:11434/v1
if not defined OPENAI_MODEL set OPENAI_MODEL=qwen3-coder:latest

REM Display configuration
echo [INFO] Configuration:
echo   OPENAI_BASE_URL: !OPENAI_BASE_URL!
echo   OPENAI_MODEL: !OPENAI_MODEL!
if defined OPENAI_API_KEY (
    echo   OPENAI_API_KEY: ***set***
) else (
    echo   OPENAI_API_KEY: ***not set***
)

REM Execute the main start script (if available) or use simplified logic
if exist "scripts\start.sh" (
    echo [INFO] Executing main startup script...
    bash scripts\start.sh %*
) else (
    echo [INFO] Using simplified Windows startup...
    
    REM Check if docker/docker-compose.yml exists
    if not exist "docker\docker-compose.yml" (
        echo [ERROR] docker/docker-compose.yml not found
        echo [ERROR] Please ensure project structure is intact
        exit /b 1
    )

    REM Check if Docker is running
    docker info >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Docker is not running or not accessible
        echo [ERROR] Please start Docker Desktop and try again
        exit /b 1
    )

    REM Determine compose command
    docker-compose --version >nul 2>&1
    if errorlevel 1 (
        docker compose version >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] docker-compose or 'docker compose' command not found
            echo [ERROR] Please install Docker Compose and try again
            exit /b 1
        ) else (
            set COMPOSE_CMD=docker compose -f docker\docker-compose.yml
        )
    ) else (
        set COMPOSE_CMD=docker-compose -f docker\docker-compose.yml
    )

    echo [INFO] Starting containers...
    !COMPOSE_CMD! up -d
    if errorlevel 1 (
        echo [ERROR] Failed to start Docker containers
        exit /b 1
    )

    echo [SUCCESS] Docker containers started successfully!
    echo [INFO] You can access qwen CLI with: !COMPOSE_CMD! exec qwen-code qwen
)

pause