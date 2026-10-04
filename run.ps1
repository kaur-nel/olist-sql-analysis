# Usage: .\run.ps1 <setup|run|test|lint|docker-run|down>
param([Parameter(Position = 0)][string]$Task = "help")

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param([string]$Command)
    Write-Host ">> $Command"
    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit code $LASTEXITCODE): $Command" }
}

switch ($Task) {
    "setup" {
        Invoke-Step "python -m pip install -r requirements.txt"
        Invoke-Step "docker compose up -d --wait db"
    }
    "run"        { Invoke-Step "python -m src.pipeline" }
    "test"       { Invoke-Step "python -m pytest -q" }
    "lint"       { Invoke-Step "python -m ruff check ." }
    "docker-run" {
        Invoke-Step "docker compose --profile pipeline build app"
        Invoke-Step "docker compose --profile pipeline run --rm app"
    }
    "down"       { Invoke-Step "docker compose --profile pipeline down" }
    default      { Write-Host "Tasks: setup run test lint docker-run down" }
}