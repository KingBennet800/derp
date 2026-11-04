<#
.SYNOPSIS
  Install, update or repair Derp on Windows. Safe to re-run; no admin needed.

.EXAMPLE
  irm https://raw.githubusercontent.com/KingBennet800/derp/main/install.ps1 | iex

.PARAMETER Engine
  Also fetch the newest engine right now.
.PARAMETER Update
  Refresh Derp's files only (what the updater runs).
.PARAMETER CI
  Non-interactive install for CI (no scheduled task).
#>
param([switch]$Engine, [switch]$Update, [switch]$CI)

$ErrorActionPreference = 'Stop'
$Src = $PSScriptRoot

# Run through `irm | iex` or as a lone file: fetch the latest release, check
# it against the release's checksums, and run its installer instead.
if (-not $Src -or -not (Test-Path (Join-Path $Src 'src\lib.ps1'))) {
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'derp-installer' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/KingBennet800/derp/releases/latest' -Headers $headers -UseBasicParsing
    $zip = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    $sums = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    $work = Join-Path $env:TEMP ('derp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work | Out-Null
    $zipPath = Join-Path $work $zip.name
    Invoke-WebRequest -Uri $zip.browser_download_url -OutFile $zipPath -UseBasicParsing -Headers $headers
    Invoke-WebRequest -Uri $sums.browser_download_url -OutFile (Join-Path $work 'SHA256SUMS') -UseBasicParsing -Headers $headers
    $line = Get-Content (Join-Path $work 'SHA256SUMS') | Where-Object { $_ -like "* $($zip.name)" } | Select-Object -First 1
    if (-not $line -or (Get-FileHash $zipPath -Algorithm SHA256).Hash -ne $line.Split(' ')[0].ToUpper()) {
        throw 'The Derp release download failed its checksum'
    }
    Expand-Archive -Path $zipPath -DestinationPath $work -Force
    $installer = Get-ChildItem -Path $work -Filter install.ps1 -Recurse | Select-Object -First 1
    $flags = @()
    if ($Engine) { $flags += '-Engine' }
    if ($Update) { $flags += '-Update' }
    if ($CI) { $flags += '-CI' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer.FullName @flags
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    return
}

. (Join-Path $Src 'src\lib.ps1')

$version = (Get-Content (Join-Path $Src 'VERSION') -Raw).Trim()
Write-Say "Installing Derp $version for Windows"
foreach ($dir in 'brand', 'config', 'lib', 'profile') {
    New-Item -ItemType Directory -Path (Join-Path $DerpHome $dir) -Force | Out-Null
}
foreach ($f in 'derp.svg', 'derp-private.svg', 'derp-splash.svg', 'derp-glyph.svg', 'derp-private-glyph.svg', 'brand.ftl', 'brand.properties', 'aboutDialog.css', 'build') {
    Copy-Item (Join-Path $Src "brand\$f") (Join-Path $DerpHome 'brand') -Recurse -Force
}
foreach ($f in 'derp-prefs.js', 'policies.json', 'distribution.ini', 'autoconfig.js', 'derp.cfg') {
    Copy-Item (Join-Path $Src "config\$f") (Join-Path $DerpHome 'config') -Force
}
foreach ($dir in 'features', 'theme') {
    $target = Join-Path $DerpHome $dir
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
}
Copy-Item (Join-Path $Src 'src\features') (Join-Path $DerpHome 'features') -Recurse
Copy-Item (Join-Path $Src 'theme') (Join-Path $DerpHome 'theme') -Recurse
foreach ($f in 'derp-patch.py', 'lib.ps1', 'derp-update.ps1') {
    $from = Join-Path $Src "src\$f"
    $to = Join-Path $DerpHome "lib\$f"
    # Keep an unchanged patcher's timestamp, so it doesn't trigger a re-brand.
    if (-not (Test-Path $to) -or (Get-FileHash $from).Hash -ne (Get-FileHash $to).Hash) { Copy-Item $from $to -Force }
}
Copy-Item (Join-Path $Src 'uninstall.ps1') (Join-Path $DerpHome 'lib\uninstall.ps1') -Force
Copy-Item (Join-Path $Src 'VERSION') (Join-Path $DerpHome 'VERSION') -Force
Get-DerpPython | Out-Null

# Start menu shortcut.
$exe = Join-Path $EngineDir 'firefox.exe'
$icon = Join-Path $DerpHome 'brand\build\derp.ico'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Derp.lnk'))
$shortcut.TargetPath = $exe
$shortcut.Arguments = "-profile `"$ProfileDir`""
$shortcut.WorkingDirectory = $EngineDir
$shortcut.IconLocation = "$icon,0"
$shortcut.Description = 'Derp web browser'
$shortcut.Save()

# Let Windows offer Derp under Settings > Apps > Default apps (per user).
$open = "`"$exe`" -profile `"$ProfileDir`" -osint -url `"%1`""
$client = 'HKCU:\Software\Clients\StartMenuInternet\Derp'
$keys = @{
    $client                                    = @{ '(default)' = 'Derp' }
    "$client\DefaultIcon"                      = @{ '(default)' = "$icon,0" }
    "$client\shell\open\command"               = @{ '(default)' = "`"$exe`" -profile `"$ProfileDir`"" }
    "$client\Capabilities"                     = @{ ApplicationName = 'Derp'; ApplicationDescription = 'A fast, fluid web browser'; ApplicationIcon = "$icon,0" }
    "$client\Capabilities\URLAssociations"     = @{ http = 'DerpURL'; https = 'DerpURL' }
    "$client\Capabilities\FileAssociations"    = @{ '.htm' = 'DerpHTML'; '.html' = 'DerpHTML'; '.pdf' = 'DerpHTML'; '.svg' = 'DerpHTML' }
    'HKCU:\Software\Classes\DerpURL'           = @{ '(default)' = 'Derp URL'; 'URL Protocol' = '' }
    'HKCU:\Software\Classes\DerpURL\DefaultIcon' = @{ '(default)' = "$icon,0" }
    'HKCU:\Software\Classes\DerpURL\shell\open\command' = @{ '(default)' = $open }
    'HKCU:\Software\Classes\DerpHTML'          = @{ '(default)' = 'Derp document' }
    'HKCU:\Software\Classes\DerpHTML\DefaultIcon' = @{ '(default)' = "$icon,0" }
    'HKCU:\Software\Classes\DerpHTML\shell\open\command' = @{ '(default)' = $open }
}
foreach ($key in $keys.Keys) {
    New-Item -Path $key -Force | Out-Null
    foreach ($value in $keys[$key].GetEnumerator()) {
        Set-ItemProperty -Path $key -Name $value.Key -Value $value.Value
    }
}
New-Item -Path 'HKCU:\Software\RegisteredApplications' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name Derp -Value 'Software\Clients\StartMenuInternet\Derp\Capabilities'

# Check for updates every 6 hours (a per-user scheduled task).
if (-not $CI) {
    try {
        $updater = Join-Path $DerpHome 'lib\derp-update.ps1'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updater`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 6)
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName 'Derp Update' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    } catch {
        Write-Say "Couldn't set up automatic updates ($($_.Exception.Message)); run $updater to update."
    }
}

$current = Get-EngineVersion $EngineDir
if (-not $current -or $Engine) {
    $latest = Get-LatestFirefoxVersion
    if (-not $current -or $Engine -or (Test-NewerVersion $latest $current)) {
        New-StagedEngine $latest
        Install-StagedEngine
        if (Test-Path $StagedDir) { Write-Say 'Derp is running; the new engine is used once you quit it' }
    }
} elseif (Test-DerpRunning) {
    Write-Say 'Derp is running; restart it to pick up the changes'
} else {
    Write-Say 'Branding the engine'
    Invoke-DerpPatch $EngineDir
}

if (-not $Update) {
    Write-Say 'Done. Open Derp from the Start menu. To make it your default browser: Settings > Apps > Default apps > Derp.'
}
