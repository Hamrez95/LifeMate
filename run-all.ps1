<#
.SYNOPSIS
A management script for running Backend, CareMate, and WellMate projects.
#>

param (
    [Alias('h')]
    [switch]$Help,

    [Alias('p')]
    [switch]$PubGet,

    [Alias('r')]
    [switch]$Run
)

# Set the script's execution path as the base path
$BasePath = $PSScriptRoot
$Projects = @("backend", "caremate", "wellmate")

# ---------------------------------------------------------
# Function to display the help message
# ---------------------------------------------------------
function Show-Help {
    Write-Host "`n🌟 Welcome to the Project Management Tool 🌟" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------"
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\run_tools.ps1 [parameters]`n"
    
    Write-Host "Available Parameters:" -ForegroundColor Yellow
    Write-Host "  -h, -Help      Displays this help message."
    Write-Host "  -p, -PubGet    Runs 'flutter pub get' for all projects."
    Write-Host "  -r, -Run       Runs the backend server and applications (in Chrome)."
    Write-Host "`nUsage Examples:" -ForegroundColor Green
    Write-Host "  .\run_tools.ps1 -h           (Show this help message)"
    Write-Host "  .\run_tools.ps1 -p           (Only get packages)"
    Write-Host "  .\run_tools.ps1 -r           (Only run the projects)"
    Write-Host "  .\run_tools.ps1 -p -r        (First get packages, then run the projects)`n"
    Write-Host "--------------------------------------------------------`n"
}

# ---------------------------------------------------------
# Function to get packages (Pub Get)
# ---------------------------------------------------------
function Run-PubGet {
    Write-Host "🚀 Checking and fetching packages..." -ForegroundColor Cyan
    foreach ($project in $Projects) {
        $ProjectPath = Join-Path -Path $BasePath -ChildPath $project
        if (Test-Path $ProjectPath) {
            Write-Host "📂 ${project}: Getting packages..." -ForegroundColor Yellow
            Push-Location $ProjectPath
            
            if ($project -eq "backend") {
                dart pub get
            } else {
                flutter pub get
            }
            
            Pop-Location
            Write-Host "✅ Packages for '${project}' updated successfully." -ForegroundColor Green
        } else {
            Write-Host "❌ Error: Directory '${project}' not found!" -ForegroundColor Red
        }
    }
    Write-Host "--------------------------------------------------------`n"
}

# ---------------------------------------------------------
# Function to run projects
# ---------------------------------------------------------
function Run-Projects {
    Write-Host "🚀 Starting services..." -ForegroundColor Cyan
    
    Write-Host "▶️ Starting backend server..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$BasePath\backend'; dart run bin/server.dart"

    Start-Sleep -Seconds 2

    Write-Host "▶️ Starting WellMate app in Chrome..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$BasePath\wellmate'; flutter run -d chrome"

    Write-Host "▶️ Starting CareMate app in Chrome..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$BasePath\caremate'; flutter run -d chrome"

    Write-Host "🎉 All services started in parallel!" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------`n"
}

# =========================================================
# Main script execution logic
# =========================================================

if ($Help -or (!$PubGet -and !$Run)) {
    Show-Help
    exit
}

if ($PubGet) {
    Run-PubGet
}

if ($Run) {
    Run-Projects
}

Write-Host "✨ All requested operations are complete. Have a great day! ✨" -ForegroundColor Cyan
Write-Host ""
