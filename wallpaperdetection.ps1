$configUrl = "https://raw.githubusercontent.com/Pr3tzals/HN-WP/main/config.json"

try {
    $config = Invoke-RestMethod -Uri $configUrl -UseBasicParsing
    $Theme = $config.theme
} catch {
    exit 0
}

$regPath = "HKCU:\Software\Intune\Wallpaper"

if (-not (Test-Path $regPath)) {
    exit 1
}

$applied = (Get-ItemProperty -Path $regPath -Name $Theme -ErrorAction SilentlyContinue).$Theme

if ($applied -eq 1) {
    exit 0
} else {
    exit 1
}