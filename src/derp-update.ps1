<#
.SYNOPSIS
  Keep Derp current on Windows: Derp itself from the latest GitHub release
  (checksum-verified) and its Firefox engine from Mozilla (verified, branded,
  staged, and swapped in while Derp isn't running). Run every 6 hours by the
  "Derp Update" scheduled task.
#>
. (Join-Path $PSScriptRoot 'lib.ps1')
$env:DERP_QUIET = '1'
$log = Join-Path $DerpHome 'update.log'
function Write-Log([string]$Message) { Add-Content -Path $log -Value "$(Get-Date -Format s) $Message" }

# One run at a time.
$lock = Join-Path $DerpHome '.update.lock'
try { $lockStream = [IO.File]::Open($lock, 'OpenOrCreate', 'ReadWrite', 'None') } catch { return }

try {
    # 1. Derp itself.
    $work = Join-Path $env:TEMP ('derp-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $release = Get-LatestRelease $work
        $tag = $release.Version
        $installed = (Get-Content (Join-Path $DerpHome 'VERSION') -Raw -ErrorAction SilentlyContinue)
        if ($installed) { $installed = $installed.Trim() }
        if (Test-NewerVersion $tag $installed) {
            Write-Log "updating Derp $installed -> $tag"
            $folder = Expand-Release $release $work
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $folder 'install.ps1') -Update -CI | Out-Null
            if ($LASTEXITCODE) { Write-Log "Derp $tag failed to install" } else { Write-Log "Derp $tag installed" }
            . (Join-Path $DerpHome 'lib\lib.ps1')
        }
    } catch {
        Write-Log "Derp update failed: $($_.Exception.Message)"
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. The engine.
    try {
        $latest = Get-LatestFirefoxVersion
        $current = Get-EngineVersion $EngineDir
        $staged = Get-EngineVersion $StagedDir
        if (-not $current -or ((Test-NewerVersion $latest $current) -and $staged -ne $latest)) {
            Write-Log "staging engine $latest (current: $current)"
            New-StagedEngine $latest
            Write-Log "engine $latest staged"
        }
    } catch {
        Write-Log "Engine update failed: $($_.Exception.Message)"
    }
    Install-StagedEngine
} finally {
    $lockStream.Close()
}
