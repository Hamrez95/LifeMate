# Start backend server in a new window
Write-Host "Starting backend server..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\backend'; dart run bin/server.dart"

# Wait a moment for server to start
Start-Sleep -Seconds 2

# Start wellmate app in Chrome
Write-Host "Starting wellmate app in Chrome..." -ForegroundColor Green
cd "$PSScriptRoot\wellmate"
flutter run -d chrome

# Start caremate app in Chrome
Write-Host "Starting caremate app in Chrome..." -ForegroundColor Green
cd "$PSScriptRoot\caremate"
flutter run -d chrome

Write-Host "3 services started!" -ForegroundColor Green
