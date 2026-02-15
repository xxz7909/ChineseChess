#!/usr/bin/env pwsh
# ============================================================
# download_pikafish.ps1
# 下载预编译的 Pikafish Android 引擎二进制文件
# 从 GitHub Releases 获取
# ============================================================

$ErrorActionPreference = "Stop"

$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
$OUTPUT_DIR = "$PROJECT_ROOT\app\android\app\src\main\jniLibs"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Pikafish 预编译二进制下载脚本" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 获取最新 release
Write-Host "`n>> 获取最新 Release 信息..." -ForegroundColor Green
try {
    $headers = @{ "Accept" = "application/vnd.github.v3+json" }
    $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/official-pikafish/Pikafish/releases/latest" -Headers $headers
    Write-Host "   最新版本: $($releaseInfo.tag_name)" -ForegroundColor Yellow
} catch {
    Write-Host "   获取 Release 信息失败: $_" -ForegroundColor Red
    Write-Host "   请手动下载: https://github.com/official-pikafish/Pikafish/releases" -ForegroundColor Yellow
    exit 1
}

# 查找 Android 构建
$armv8Asset = $releaseInfo.assets | Where-Object { $_.name -match "android.*armv8|armv8.*android|aarch64.*android" } | Select-Object -First 1
$armv7Asset = $releaseInfo.assets | Where-Object { $_.name -match "android.*armv7|armv7.*android" } | Select-Object -First 1

function Download-AndExtract {
    param(
        [object]$Asset,
        [string]$AbiName,
        [string]$ArchLabel
    )

    if (-not $Asset) {
        Write-Host "   未找到 $ArchLabel 的预编译文件" -ForegroundColor Yellow
        Write-Host "   可尝试手动编译: .\scripts\build_pikafish.ps1" -ForegroundColor Yellow
        return $false
    }

    $outputDir = "$OUTPUT_DIR\$AbiName"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    $downloadUrl = $Asset.browser_download_url
    $fileName = $Asset.name
    $tempFile = "$env:TEMP\$fileName"

    Write-Host "`n>> 下载 $ArchLabel : $fileName" -ForegroundColor Green
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile

    # 解压
    if ($fileName -match "\.zip$") {
        $extractDir = "$env:TEMP\pikafish_extract_$AbiName"
        if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
        Expand-Archive -Path $tempFile -DestinationPath $extractDir -Force

        # 查找可执行文件
        $exeFile = Get-ChildItem $extractDir -Recurse -File | Where-Object {
            $_.Name -match "pikafish" -and $_.Name -notmatch "\.(txt|md|nnue)$"
        } | Select-Object -First 1

        if ($exeFile) {
            Copy-Item $exeFile.FullName "$outputDir\libpikafish.so" -Force
            Write-Host "   >> 输出: $outputDir\libpikafish.so" -ForegroundColor Green
        } else {
            Write-Host "   解压后未找到 pikafish 可执行文件" -ForegroundColor Red
            return $false
        }

        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    } elseif ($fileName -match "\.tar") {
        # tar 解压
        $extractDir = "$env:TEMP\pikafish_extract_$AbiName"
        if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
        tar -xf $tempFile -C $extractDir

        $exeFile = Get-ChildItem $extractDir -Recurse -File | Where-Object {
            $_.Name -match "pikafish" -and $_.Name -notmatch "\.(txt|md|nnue)$"
        } | Select-Object -First 1

        if ($exeFile) {
            Copy-Item $exeFile.FullName "$outputDir\libpikafish.so" -Force
            Write-Host "   >> 输出: $outputDir\libpikafish.so" -ForegroundColor Green
        } else {
            Write-Host "   解压后未找到 pikafish 可执行文件" -ForegroundColor Red
            return $false
        }

        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    } else {
        # 直接就是可执行文件
        Copy-Item $tempFile "$outputDir\libpikafish.so" -Force
        Write-Host "   >> 输出: $outputDir\libpikafish.so" -ForegroundColor Green
    }

    Remove-Item $tempFile -ErrorAction SilentlyContinue
    return $true
}

# 显示所有可用的 assets
Write-Host "`n>> 可用的 Release Assets:" -ForegroundColor Yellow
foreach ($asset in $releaseInfo.assets) {
    $marker = ""
    if ($asset -eq $armv8Asset) { $marker = " <-- arm64-v8a" }
    if ($asset -eq $armv7Asset) { $marker = " <-- armeabi-v7a" }
    Write-Host "   - $($asset.name)$marker" -ForegroundColor Gray
}

$success = $false

# 下载
if ($armv8Asset) {
    $success = Download-AndExtract -Asset $armv8Asset -AbiName "arm64-v8a" -ArchLabel "ARM64 (arm64-v8a)"
}
if ($armv7Asset) {
    $r = Download-AndExtract -Asset $armv7Asset -AbiName "armeabi-v7a" -ArchLabel "ARM32 (armeabi-v7a)"
    if ($r) { $success = $true }
}

if (-not $success) {
    Write-Host "`n====================================================" -ForegroundColor Yellow
    Write-Host "  未能自动下载预编译文件。" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  请手动操作：" -ForegroundColor Yellow
    Write-Host "  1. 访问 https://github.com/official-pikafish/Pikafish/releases" -ForegroundColor Yellow
    Write-Host "  2. 下载 Android ARM64 和 ARM32 版本" -ForegroundColor Yellow
    Write-Host "  3. 将可执行文件重命名为 libpikafish.so 并放到：" -ForegroundColor Yellow
    Write-Host "     $OUTPUT_DIR\arm64-v8a\libpikafish.so" -ForegroundColor Yellow
    Write-Host "     $OUTPUT_DIR\armeabi-v7a\libpikafish.so" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Yellow
} else {
    Write-Host "`n====================================================" -ForegroundColor Cyan
    Write-Host "  下载完成！" -ForegroundColor Cyan
    Write-Host "  输出目录: $OUTPUT_DIR" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
}
