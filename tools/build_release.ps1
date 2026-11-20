# Builds a signed release APK: build/SimAntics-<version>.apk
#
# One-time setup: create a release keystore OUTSIDE the project folder and keep it
# (and its password) safe. Losing it means you can never update the app on Play.
#
#   keytool -genkeypair -v -keystore "$HOME\keys\simantics-release.keystore" -alias simantics `
#           -keyalg RSA -keysize 2048 -validity 10000
#
# Then run from the project folder:
#   .\tools\build_release.ps1
#
# Optional parameters: -Keystore <path> -Alias <name> -Godot <path to Godot exe>
param(
    [string]$Keystore = "$HOME\keys\simantics-release.keystore",
    [string]$Alias = "simantics",
    [string]$Godot = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.2-stable_win64.exe"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Keystore)) { throw "Keystore not found: $Keystore (see the setup note at the top of this script)" }
if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot (pass -Godot <path>)" }

$version = (Select-String -Path "$project\export_presets.cfg" -Pattern '^version/name="(.+)"').Matches[0].Groups[1].Value
$output = "build/SimAntics-$version.apk"
New-Item -ItemType Directory -Force "$project\build" | Out-Null

# The password is only held in this process's environment for the export; it is never written to disk.
$secure = Read-Host "Keystore password" -AsSecureString
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = (Resolve-Path $Keystore).Path
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $Alias
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [System.Net.NetworkCredential]::new("", $secure).Password
try {
    & $Godot --headless --path $project --import | Out-Null
    & $Godot --headless --path $project --export-release "Android" $output
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed (exit $LASTEXITCODE)" }
}
finally {
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
}

# Confirm the APK is signed with the release key, not the debug one.
$apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Recurse -Filter apksigner.bat |
    Sort-Object FullName -Descending | Select-Object -First 1
& $apksigner.FullName verify --print-certs "$project\$output"
Write-Host "`nRelease APK: $project\$output"
