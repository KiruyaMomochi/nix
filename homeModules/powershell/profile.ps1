# $env:HOME/.config/powershell/Microsoft.PowerShell_profile.ps1

Get-ChildItem "$PROFILE\..\Completions\" | ForEach-Object {
    . $_.FullName
}
