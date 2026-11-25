param(
  [switch]$Install
)

$ErrorActionPreference = "Stop"

$fl = "C:\src\flutter\bin\flutter.bat"
$jdk21 = Join-Path $env:USERPROFILE ".jdks\openjdk-21.0.1"
$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"

if (Test-Path (Join-Path $jdk21 "bin\java.exe")) {
  $env:JAVA_HOME = $jdk21
}
if (Test-Path $sdk) {
  $env:ANDROID_HOME = $sdk
  $env:ANDROID_SDK_ROOT = $sdk
}

Push-Location $PSScriptRoot
try {
  Write-Host "Compilation de l'APK Flutter Release XFY (natif 60/120fps)..." -ForegroundColor Cyan
  & $fl build apk --release
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  # Libérer la RAM Gradle après compilation
  $gradlew = Join-Path $PSScriptRoot "android\gradlew.bat"
  if (Test-Path $gradlew) {
    Push-Location (Join-Path $PSScriptRoot "android")
    try { .\gradlew.bat --stop | Out-Null } finally { Pop-Location }
  }

  $apk = Join-Path $PSScriptRoot "build\app\outputs\flutter-apk\app-release.apk"
  Write-Host ""
  Write-Host "APK Flutter Release pret :" -ForegroundColor Green
  Write-Host "  $apk" -ForegroundColor Yellow

  if ($Install) {
    $adb = Join-Path $sdk "platform-tools\adb.exe"
    $devices = & $adb devices | Select-String "\tdevice$"
    if ($devices) {
      Write-Host "Installation sur votre telephone USB..." -ForegroundColor Cyan
      & $adb install -r $apk
      if ($LASTEXITCODE -eq 0) {
        & $adb shell monkey -p tn.xfy.xfy_mobile -c android.intent.category.LAUNCHER 1 | Out-Null
      }
    } else {
      Write-Host "Aucun telephone USB detecte. Copiez l'APK ci-dessus sur votre telephone." -ForegroundColor Yellow
    }
  }
} finally {
  Pop-Location
}
