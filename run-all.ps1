Write-Host "Starting backend server..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\backend'; dart run bin/server.dart"

Start-Sleep -Seconds 2

Write-Host "Starting WellMate app in Chrome..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\wellmate'; flutter run -d chrome"

Write-Host "Starting CareMate app in Chrome..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\caremate'; flutter run -d chrome"

Write-Host "All services started in parallel!" -ForegroundColor Green
