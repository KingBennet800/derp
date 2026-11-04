# Derp PowerShell library for Windows, dot-sourced by install.ps1 and
# derp-update.ps1. Written for Windows PowerShell 5.1, which every Windows 10
# and 11 machine has.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # the progress bar makes downloads crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$DerpRepo = 'KingBennet800/derp'
$Ftp = 'https://ftp.mozilla.org/pub/firefox/releases'
$DerpHome = Join-Path $env:LOCALAPPDATA 'Derp'
$EngineDir = Join-Path $DerpHome 'firefox'
$StagedDir = Join-Path $DerpHome 'firefox.next'
$ProfileDir = Join-Path $DerpHome 'profile'
$Headers = @{ 'User-Agent' = 'derp-installer' }

# Python's official embeddable build, pinned by checksum, for the branding patcher.
$PythonVersion = '3.12.10'
$PythonSha256 = @{
    amd64 = '4acbed6dd1c744b0376e3b1cf57ce906f9dc9e95e68824584c8099a63025a3c3'
    arm64 = '3065efc3d382d1cda66757ac71ade11904fa6e350f5a97eb74811acd71ba5532'
}

function Write-Say([string]$Message) {
    if (-not $env:DERP_QUIET) { Write-Host "> $Message" -ForegroundColor Cyan }
}

function Get-DerpArch {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
}

function Save-Url([string]$Url, [string]$Path) {
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -Headers $Headers
}

function Test-NewerVersion([string]$A, [string]$B) {
    # Is dotted version $A newer than $B? ("159.0.1" vs "159.0")
    if (-not $B) { return [bool]$A }
    $pa = $A.Split('.') | ForEach-Object { [int]$_ }
    $pb = $B.Split('.') | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -ne $y) { return $x -gt $y }
    }
    return $false
}

function Get-LatestFirefoxVersion {
    (Invoke-RestMethod -Uri 'https://product-details.mozilla.org/1.0/firefox_versions.json' -UseBasicParsing).LATEST_FIREFOX_VERSION
}

function Get-EngineVersion([string]$Dir) {
    $ini = Join-Path $Dir 'application.ini'
    if (-not (Test-Path $ini)) { return $null }
    $line = Get-Content $ini | Where-Object { $_ -like 'Version=*' } | Select-Object -First 1
    if ($line) { $line.Substring(8) } else { $null }
}

function Test-DerpRunning {
    $exe = Join-Path $EngineDir 'firefox.exe'
    [bool](Get-Process -Name firefox -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
}

function Get-DerpPython {
    $python = Join-Path $DerpHome 'python\python.exe'
    if (Test-Path $python) { return $python }
    $arch = Get-DerpArch
    Write-Say "Fetching Python $PythonVersion for Derp's patcher"
    $zip = Join-Path $env:TEMP "derp-python-$arch.zip"
    Save-Url "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-$arch.zip" $zip
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $PythonSha256[$arch].ToUpper()) {
        Remove-Item $zip -Force
        throw "Python download failed its checksum"
    }
    Expand-Archive -Path $zip -DestinationPath (Join-Path $DerpHome 'python') -Force
    Remove-Item $zip -Force
    return $python
}

function Get-ShortPath([string]$Path) {
    # Firefox's installer can't take quoted paths, so avoid spaces (8.3 names).
    if ($Path -notmatch ' ') { return $Path }
    (New-Object -ComObject Scripting.FileSystemObject).GetFolder($Path).ShortPath
}

# Download, verify and unpack Firefox $Version into $Work; returns the engine folder.
function Get-Firefox([string]$Version, [string]$Work) {
    $platform = if ((Get-DerpArch) -eq 'arm64') { 'win64-aarch64' } else { 'win64' }
    $file = "$platform/en-US/Firefox Setup $Version.exe"
    $setup = Join-Path $Work 'FirefoxSetup.exe'
    Write-Say "Downloading the Firefox $Version engine from ftp.mozilla.org"
    Save-Url "$Ftp/$Version/SHA256SUMS" (Join-Path $Work 'SHA256SUMS')
    Save-Url ("$Ftp/$Version/" + ($file -replace ' ', '%20')) $setup

    Write-Say "Verifying Mozilla's checksum and signature"
    $line = Get-Content (Join-Path $Work 'SHA256SUMS') | Where-Object { $_ -like "*  $file" } | Select-Object -First 1
    if (-not $line) { throw "No checksum for $file in Mozilla's SHA256SUMS" }
    if ((Get-FileHash $setup -Algorithm SHA256).Hash -ne $line.Split(' ')[0].ToUpper()) { throw "Checksum mismatch for $file" }
    $sig = Get-AuthenticodeSignature $setup
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Mozilla Corporation') {
        throw "Firefox's installer isn't validly signed by Mozilla ($($sig.Status))"
    }

    # The full installer can unpack itself without installing anything.
    $out = Join-Path $Work 'unpacked'
    New-Item -ItemType Directory -Path $out | Out-Null
    $proc = Start-Process -FilePath $setup -ArgumentList "/ExtractDir=$(Get-ShortPath $out)" -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Firefox's installer failed to unpack (exit $($proc.ExitCode))" }
    $engine = Get-ChildItem -Path $out -Filter firefox.exe -Recurse | Select-Object -First 1
    if (-not $engine) { throw "Firefox's installer unpacked no firefox.exe" }
    Remove-Item $setup -Force
    return $engine.DirectoryName
}

function Invoke-DerpPatch([string]$Engine) {
    $env:DERP_HOME = $DerpHome
    $env:DERP_ENGINE = $Engine
    & (Get-DerpPython) -I (Join-Path $DerpHome 'lib\derp-patch.py') | Out-Null
    $code = $LASTEXITCODE
    Remove-Item Env:\DERP_ENGINE
    if ($code -ne 0 -and $code -ne 3) { throw "Branding the engine failed (exit $code)" }
}

# Fetch, verify and brand Firefox $Version into firefox.next.
function New-StagedEngine([string]$Version) {
    $work = Join-Path $env:TEMP ("derp-engine-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $engine = Get-Firefox $Version $work
        Write-Say "Branding engine $Version"
        Invoke-DerpPatch $engine
        New-Item -ItemType File -Path (Join-Path $engine '.derp-ready') -Force | Out-Null
        if (Test-Path $StagedDir) { Remove-Item $StagedDir -Recurse -Force }
        Move-Item $engine $StagedDir
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Swap the staged engine in, unless Derp is running (then the next update run does).
function Install-StagedEngine {
    if (-not (Test-Path (Join-Path $StagedDir '.derp-ready'))) { return }
    if (Test-DerpRunning) { return }
    $old = "$EngineDir.old"
    if (Test-Path $old) { Remove-Item $old -Recurse -Force }
    if (Test-Path $EngineDir) { Rename-Item $EngineDir (Split-Path $old -Leaf) }
    Rename-Item $StagedDir (Split-Path $EngineDir -Leaf)
    Remove-Item (Join-Path $EngineDir '.derp-ready') -Force
    Remove-Item $old -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-LatestRelease {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$DerpRepo/releases/latest" -Headers $Headers -UseBasicParsing
}

# Download a release's zip, check it against the release's SHA256SUMS and
# unpack it; returns the folder holding its install.ps1.
function Expand-Release($Release, [string]$Work) {
    $zip = $Release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    $sums = $Release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $zip -or -not $sums) { throw "The latest Derp release has no zip or SHA256SUMS" }
    $zipPath = Join-Path $Work $zip.name
    Save-Url $zip.browser_download_url $zipPath
    Save-Url $sums.browser_download_url (Join-Path $Work 'SHA256SUMS')
    $line = Get-Content (Join-Path $Work 'SHA256SUMS') | Where-Object { $_ -like "* $($zip.name)" } | Select-Object -First 1
    if (-not $line -or (Get-FileHash $zipPath -Algorithm SHA256).Hash -ne $line.Split(' ')[0].ToUpper()) {
        throw "The Derp release download failed its checksum"
    }
    Expand-Archive -Path $zipPath -DestinationPath $Work -Force
    (Get-ChildItem -Path $Work -Filter install.ps1 -Recurse | Select-Object -First 1).DirectoryName
}
