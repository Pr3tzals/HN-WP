<#
.SYNOPSIS
Wallpaper deployment with optional lock enforcement
#>

# ================= CONFIG =================
$configUrl    = "https://raw.githubusercontent.com/Pr3tzals/HN-WP/main/config.json"
$FolderRoot   = "C:\Intune\Wallpaper"
$LogsFolder   = Join-Path $FolderRoot "Logs"
$RegistryFlag = "HKCU:\Software\Intune\Wallpaper"

$EnforceLock  = $false   # TRUE = lock wallpaper, FALSE = allow changes
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

function Apply-WallpaperPolicy {
    try {
        $policyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"

        try {
            if (-not (Test-Path $policyPath)) {
                New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
            }
        } catch {
            Write-Log "Could not create policy registry path (likely managed by policy or restricted): $($_.Exception.Message)" "WARN"
            return
        }

        if ($EnforceLock) {
            Set-ItemProperty -Path $policyPath -Name "NoChangingWallPaper" -Value 1 -Type DWord
            Write-Log "Wallpaper changes are LOCKED."
        } else {
            Remove-ItemProperty -Path $policyPath -Name "NoChangingWallPaper" -ErrorAction SilentlyContinue
            Write-Log "Wallpaper changes are ALLOWED."
        }

    } catch {
        Write-Log "Failed to apply lock policy: $($_.Exception.Message)" "WARN"
    }
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

# --- Check if theme already applied ---
$applied = (Get-ItemProperty -Path $RegistryFlag -Name $Theme -ErrorAction SilentlyContinue).$Theme

if ($applied -eq 1) {
    Write-Log "Theme $Theme already applied. Skipping download."

    Apply-WallpaperPolicy
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

    $themesDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    Remove-Item "$themesDir\TranscodedWallpaper" -Force -ErrorAction SilentlyContinue

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

    Start-Sleep -Seconds 2

    $appliedWallpaper = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

    if ($appliedWallpaper -and ($appliedWallpaper.ToLower() -ne $WallpaperFile.ToLower())) {

        Write-Log "Wallpaper not reflected yet. Restarting Explorer..."

        try {
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Process explorer.exe
            Write-Log "Explorer restarted."
        } catch {
            Write-Log "Explorer restart failed: $($_.Exception.Message)" "WARN"
        }

    } else {
        Write-Log "Wallpaper applied successfully."
    }

} catch {
    Write-Log "Failed to apply wallpaper: $($_.Exception.Message)" "ERROR"
    exit 0
}

# --- Mark applied ---
New-ItemProperty -Path $RegistryFlag -Name $Theme -Value 1 -PropertyType DWord -Force | Out-Null
Write-Log "Theme $Theme marked as applied."

# --- Apply lock policy ---
Apply-WallpaperPolicy

exit 0