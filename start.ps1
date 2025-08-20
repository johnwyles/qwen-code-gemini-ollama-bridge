# Qwen Code Docker Startup Script (PowerShell)
# Handles container states, rebuilds, and data persistence

param(
    [switch]$Rebuild,
    [alias("r")][switch]$R
)

# Error handling
$ErrorActionPreference = "Stop"

# Color functions for output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

try {
    # Check for --rebuild flag
    $ForceRebuild = $Rebuild -or $R
    if ($ForceRebuild) {
        Write-Info "Force rebuild requested"
    }

    Write-Info "Starting Qwen Code Docker Environment..."

    # Check if .env exists
    if (-not (Test-Path ".env")) {
        Write-Warning ".env file not found. Please create one manually or run the setup wizard"
        Write-Error "Create a .env file with your configuration"
        exit 1
    }

    # Clear any potentially conflicting environment variables
    Write-Info "Clearing conflicting environment variables..."
    Remove-Item env:OPENAI_API_KEY -ErrorAction SilentlyContinue
    Remove-Item env:OPENAI_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item env:OPENAI_MODEL -ErrorAction SilentlyContinue
    Remove-Item env:GEMINI_DEFAULT_AUTH_TYPE -ErrorAction SilentlyContinue
    Remove-Item env:USE_GEMINI_BRIDGE -ErrorAction SilentlyContinue
    Remove-Item env:BRIDGE_TARGET_URL -ErrorAction SilentlyContinue
    Remove-Item env:BRIDGE_PORT -ErrorAction SilentlyContinue
    Remove-Item env:BRIDGE_DEBUG -ErrorAction SilentlyContinue

    # Load .env file
    Write-Info "Loading environment from .env file..."
    Get-Content .env | Where-Object { $_ -notmatch "^#" -and $_ -ne "" } | ForEach-Object {
        $key, $value = $_ -split "=", 2
        if ($key -and $value) {
            Set-Item -Path "env:$key" -Value $value
        }
    }

    # Set default environment variables
    if (-not $env:OPENAI_BASE_URL) { $env:OPENAI_BASE_URL = "http://localhost:11434/v1" }
    if (-not $env:OPENAI_MODEL) { $env:OPENAI_MODEL = "qwen3-coder:latest" }

    # Display configuration
    Write-Info "Configuration:"
    Write-Host "  OPENAI_BASE_URL: $($env:OPENAI_BASE_URL)"
    Write-Host "  OPENAI_MODEL: $($env:OPENAI_MODEL)"
    Write-Host "  QWEN_CONFIG_PATH: /home/qwen/.config"
    if ($env:OPENAI_API_KEY) {
        Write-Host "  OPENAI_API_KEY: ***set***"
    } else {
        Write-Host "  OPENAI_API_KEY: ***not set***"
    }

    # Execute the main start script (if available) or use simplified logic
    if (Test-Path "scripts\start.sh") {
        Write-Info "Executing main startup script..."
        & bash scripts\start.sh @args
    } else {
        Write-Info "Using simplified Windows startup..."
        
        # Check if docker/docker-compose.yml exists
        if (-not (Test-Path "docker\docker-compose.yml")) {
            Write-Error "docker/docker-compose.yml not found"
            Write-Error "Please ensure project structure is intact"
            exit 1
        }

        # Check if Docker is running
        try {
            & docker info | Out-Null
        } catch {
            Write-Error "Docker is not running or not accessible"
            Write-Error "Please start Docker Desktop and try again"
            exit 1
        }

        # Check if docker-compose is available
        $composeCmd = ""
        try {
            & docker-compose --version | Out-Null
            $composeCmd = "docker-compose -f docker\docker-compose.yml"
        } catch {
            try {
                & docker compose version | Out-Null
                $composeCmd = "docker compose -f docker\docker-compose.yml"
            } catch {
                Write-Error "docker-compose or 'docker compose' command not found"
                Write-Error "Please install Docker Compose and try again"
                exit 1
            }
        }

        Write-Info "Starting containers..."
        $composeArgs = $composeCmd -split " "
        & $composeArgs[0] $composeArgs[1..($composeArgs.Length-1)] up -d
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start Docker containers"
            exit 1
        }

        Write-Success "Docker containers started successfully!"
        Write-Info "You can access qwen CLI with: $composeCmd exec qwen-code qwen"
    }

} catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    exit 1
}