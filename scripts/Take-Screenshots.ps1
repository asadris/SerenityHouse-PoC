# Take-Screenshots.ps1
# Captures one screenshot per Power BI Desktop page and saves them to screenshots/
#
# Usage (from PowerShell, run as normal user — no elevation needed):
#   cd "D:\OneDrive\Serenity House\SerenityPOC Repo"
#   .\scripts\Take-Screenshots.ps1
#
# Requirements:
#   - Power BI Desktop must be open with SerenityPOC2
#   - Navigate to the FIRST page manually before running
#   - The report must be in normal view (not focus/fullscreen mode)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
$pages = @(
    "01_Synthetic_Data_Notice",
    "02_Early_Warning",
    "03_Master_Roster",
    "04_Arrears",
    "05_Rent",
    "06_Behaviors",
    "07_Bed_Stay",
    "08_Demographics",
    "09_Referrals",
    "10_Areas_Served",
    "11_Donations",
    "12_Funding",
    "13_Resident_Profile",
    "14_Program_Outcomes"
)

$outputDir = "$PSScriptRoot\..\screenshots"
$delayBetweenPages = 3   # seconds — increase if your machine is slow
$delayAfterFocus   = 1   # seconds to wait after bringing window to foreground

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    Write-Host "Created: $outputDir"
}

# Find Power BI Desktop window
$pbiProcess = Get-Process | Where-Object { $_.MainWindowTitle -like "*SerenityPOC2*" } | Select-Object -First 1

if (-not $pbiProcess) {
    Write-Error "Power BI Desktop window with 'SerenityPOC2' not found. Make sure it's open."
    exit 1
}

Write-Host "Found Power BI Desktop: '$($pbiProcess.MainWindowTitle)'"
Write-Host "Output folder: $outputDir"
Write-Host ""
Write-Host "Make sure you are on the FIRST page (Synthetic Data Notice) before continuing."
Write-Host ""
Read-Host "Press Enter to start..."

# ---------------------------------------------------------------------------
# Screenshot function
# ---------------------------------------------------------------------------
function Take-Screenshot {
    param([string]$filePath)

    $screen  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap  = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
    $graphic = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphic.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphic.Dispose()
    $bitmap.Dispose()
}

# ---------------------------------------------------------------------------
# Main loop — bring PBI to foreground, screenshot, advance page
# ---------------------------------------------------------------------------
for ($i = 0; $i -lt $pages.Count; $i++) {
    $pageName = $pages[$i]

    # Bring Power BI Desktop to foreground and maximize
    [Win32]::ShowWindow($pbiProcess.MainWindowHandle, 3)  # SW_MAXIMIZE
    [Win32]::SetForegroundWindow($pbiProcess.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds $delayAfterFocus

    $filePath = Join-Path $outputDir "$pageName.png"
    Take-Screenshot -filePath $filePath
    Write-Host "[$($i+1)/$($pages.Count)] Saved: $pageName.png"

    # Advance to next page (skip on last iteration)
    if ($i -lt $pages.Count - 1) {
        [System.Windows.Forms.SendKeys]::SendWait("^{TAB}")   # Ctrl+Tab to highlight next page tab
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") # Enter to navigate to it
        Start-Sleep -Seconds $delayBetweenPages
    }
}

Write-Host ""
Write-Host "Done! $($pages.Count) screenshots saved to:"
Write-Host "  $((Resolve-Path $outputDir).Path)"
