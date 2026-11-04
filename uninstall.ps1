<#
.SYNOPSIS
  Remove Derp from Windows. Your profile (bookmarks, history, logins) is kept
  unless you pass -Purge.
#>
param([switch]$Purge)
$ErrorActionPreference = 'Stop'
$DerpHome = Join-Path $env:LOCALAPPDATA 'Derp'

Unregister-ScheduledTask -TaskName 'Derp Update' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'Derp.lnk') -Force -ErrorAction SilentlyContinue
foreach ($key in 'HKCU:\Software\Clients\StartMenuInternet\Derp', 'HKCU:\Software\Classes\DerpURL', 'HKCU:\Software\Classes\DerpHTML') {
    Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name Derp -ErrorAction SilentlyContinue

if ($Purge) {
    Remove-Item $DerpHome -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Derp and its profile are gone.'
} else {
    Get-ChildItem $DerpHome -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'profile' } | Remove-Item -Recurse -Force
    Write-Host "Derp removed. Your profile is still in $DerpHome\profile (use -Purge to delete it)."
}
