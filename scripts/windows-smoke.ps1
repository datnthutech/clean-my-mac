# Launches the published Windows app on every page, checks it stays alive and screenshots each page.
# Usage: scripts/windows-smoke.ps1 -Exe <path to CleanMyMac.exe> -Out screenshots
param([Parameter(Mandatory)][string]$Exe, [string]$Out = "screenshots")
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Save-Screen([string]$Path) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Run-Page([string]$Name, [string[]]$Arguments, [int]$Seconds) {
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru
    Start-Sleep -Seconds $Seconds
    if ($p.HasExited) { throw "App exited early (code $($p.ExitCode)) on page '$Name'" }
    Save-Screen (Join-Path $Out "page-$Name.png")
    Stop-Process -Id $p.Id -Force
    Start-Sleep -Seconds 2
}

# Fresh settings so the welcome dialog shows once, in Vietnamese-capable culture.
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\CleanMyMac" -ErrorAction SilentlyContinue
Run-Page "0-onboarding" @() 12

foreach ($page in "summary", "drive", "duplicates", "docker", "log", "help", "settings") {
    Run-Page $page @("--skip-onboarding", "--open-page", $page) 10
}

# A real scan of the system drive; the page shows the result once finished.
$p = Start-Process -FilePath $Exe -ArgumentList @("--skip-onboarding", "--scan-on-launch", "--open-page", "duplicates") -PassThru
for ($i = 0; $i -lt 18; $i++) {
    Start-Sleep -Seconds 10
    if ($p.HasExited) { throw "App exited while scanning (code $($p.ExitCode))" }
}
Save-Screen (Join-Path $Out "page-scanned-duplicates.png")
Stop-Process -Id $p.Id -Force
Write-Host "Smoke test passed"
