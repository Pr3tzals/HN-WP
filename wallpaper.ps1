<#
.SYNOPSIS
Applies wallpaper from a central JSON configuration when a new theme is published via Intune Proactive Remediation.
The wallpaper is forced once per theme, after which users can freely change it until the next update.

.AUTHOR
Fabio Figueiredo

.DESIGN
- New theme = force apply
- Same theme = do nothing
- Allows user changes after application
- Restarts Explorer only if required
- Designed for daily Proactive Remediation execution

.NOTES
- Must run in USER context (HKCU)
#>

# ================= CONFIG =================
$configUrl    = "https://raw.githubusercontent.com/Pr3tzals/HN-WP/main/config.json"
$FolderRoot   = "C:\Intune\Wallpaper"
$LogsFolder   = Join-Path $FolderRoot "Logs"
$RegistryFlag = "HKCU:\Software\Intune\Wallpaper"
# =========================================

function Write-Log {
    param([string]$Message,[string]$Level="INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Output $line

    try {
        if (-not (Test-Path $LogsFolder)) {
            New-Item -Path $LogsFolder -ItemType Directory -Force | Out-Null
        }
        $logFile = Join-Path $LogsFolder "Wallpaper_$(Get-Date -Format 'yyyyMMdd').log"
        Add-Content -Path $logFile -Value $line
    } catch {}
}

# --- Load JSON config ---
try {
    $config = Invoke-RestMethod -Uri $configUrl -UseBasicParsing
    $Theme = $config.theme
    $WallpaperUrl = $config.url
    Write-Log "Loaded config: Theme=$Theme"
} catch {
    Write-Log "Failed to load config: $($_.Exception.Message)" "ERROR"
    exit 0
}

# Ensure registry exists
if (-not (Test-Path $RegistryFlag)) {
    New-Item -Path $RegistryFlag -Force | Out-Null
}

# --- Check if this theme already applied ---
$applied = (Get-ItemProperty -Path $RegistryFlag -Name $Theme -ErrorAction SilentlyContinue).$Theme

if ($applied -eq 1) {
    Write-Log "Theme $Theme already applied. Nothing to do."
    exit 0
}

# --- Prep folders ---
New-Item -Path $FolderRoot -ItemType Directory -Force | Out-Null
$ThemeFolder = Join-Path $FolderRoot $Theme
New-Item -Path $ThemeFolder -ItemType Directory -Force | Out-Null

# --- File path ---
$extension = [System.IO.Path]::GetExtension($WallpaperUrl)
if ([string]::IsNullOrWhiteSpace($extension)) { $extension = ".png" }

$WallpaperFile = Join-Path $ThemeFolder ("wallpaper" + $extension)

# --- Download wallpaper ---
try {
    Write-Log "Downloading wallpaper from $WallpaperUrl"
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallpaperFile -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Log "Download failed: $($_.Exception.Message)" "ERROR"
    exit 0
}

# --- Apply wallpaper ---
try {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $WallpaperFile
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '2'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

    # Reset theme cache
    $themesDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    Remove-Item "$themesDir\TranscodedWallpaper" -Force -ErrorAction SilentlyContinue

    # Apply via Windows API
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    [Wallpaper]::SystemParametersInfo(20, 0, $WallpaperFile, 3) | Out-Null

    Write-Log "Wallpaper applied via API."

    # --- Validate application ---
    Start-Sleep -Seconds 2

    $appliedWallpaper = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

    if ($appliedWallpaper -and ($appliedWallpaper.ToLower() -ne $WallpaperFile.ToLower())) {
        Write-Log "Wallpaper not reflected yet. Restarting Explorer..."

        try {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Process explorer.exe
            Write-Log "Explorer restarted to finalize wallpaper update."
        } catch {
            Write-Log "Explorer restart failed: $($_.Exception.Message)" "WARN"
        }
    } else {
        Write-Log "Wallpaper applied successfully. Explorer restart not required."
    }

} catch {
    Write-Log "Failed to apply wallpaper: $($_.Exception.Message)" "ERROR"
    exit 0
}

# --- Mark as applied ---
New-ItemProperty -Path $RegistryFlag -Name $Theme -Value 1 -PropertyType DWord -Force | Out-Null

Write-Log "Theme $Theme marked as applied."
exit 0