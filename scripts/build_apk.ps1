#!/usr/bin/env pwsh
# ============================================================
# build_apk.ps1
# 一键构建中国象棋 APK
# ============================================================

$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
$APP_DIR = "$PROJECT_ROOT\app"
$JNILIBS_DIR = "$APP_DIR\android\app\src\main\jniLibs"

# 环境变量
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = "$env:LOCALAPPDATA\Android\Sdk"
$env:JAVA_HOME = "C:\JDK17\jdk-17"
$env:Path = "C:\flutter\bin;$env:JAVA_HOME\bin;$env:Path"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  中国象棋 APK 构建脚本" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ============================================================
# 检查引擎二进制文件
# ============================================================
$arm64Lib = "$JNILIBS_DIR\arm64-v8a\libpikafish.so"
$arm32Lib = "$JNILIBS_DIR\armeabi-v7a\libpikafish.so"

if (-not (Test-Path $arm64Lib) -and -not (Test-Path $arm32Lib)) {
    Write-Host "`n>> 未找到 Pikafish 引擎二进制文件" -ForegroundColor Yellow
    Write-Host "   正在尝试下载..." -ForegroundColor Yellow
    & "$PROJECT_ROOT\scripts\download_pikafish.ps1"

    if (-not (Test-Path $arm64Lib) -and -not (Test-Path $arm32Lib)) {
        Write-Host "`n!! 仍未找到引擎文件。APK将无法使用引擎功能。" -ForegroundColor Red
        Write-Host "   请参考 README.md 手动放置引擎文件" -ForegroundColor Yellow
    }
}

if (Test-Path $arm64Lib) {
    $size = (Get-Item $arm64Lib).Length / 1MB
    Write-Host "   arm64-v8a: $([math]::Round($size, 2)) MB" -ForegroundColor Green
}
if (Test-Path $arm32Lib) {
    $size = (Get-Item $arm32Lib).Length / 1MB
    Write-Host "   armeabi-v7a: $([math]::Round($size, 2)) MB" -ForegroundColor Green
}

# ============================================================
# Flutter 构建
# ============================================================
Write-Host "`n>> 检查 Flutter 环境..." -ForegroundColor Green
flutter --version

Write-Host "`n>> 获取依赖..." -ForegroundColor Green
Push-Location $APP_DIR
flutter pub get

Write-Host "`n>> 构建 APK (release)..." -ForegroundColor Green
flutter build apk --release --split-per-abi

Pop-Location

# ============================================================
# 输出信息
# ============================================================
$apkDir = "$APP_DIR\build\app\outputs\flutter-apk"
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "  构建完成！" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Cyan
if (Test-Path "$apkDir") {
    Get-ChildItem "$apkDir\*.apk" | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host "  $($_.Name) ($sizeMB MB)" -ForegroundColor Green
    }
    Write-Host "" -ForegroundColor Cyan
    Write-Host "  APK 位置: $apkDir" -ForegroundColor Cyan
}
Write-Host "====================================================" -ForegroundColor Cyan
