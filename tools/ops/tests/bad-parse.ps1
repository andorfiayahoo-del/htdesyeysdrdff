# bad-parse.ps1 - deliberately invalid PowerShell
param()
$x = @("ok", )
Write-Host "You should never see this line."