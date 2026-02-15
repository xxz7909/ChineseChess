#!/usr/bin/env pwsh
# ============================================================
# build_pikafish.ps1
# 下载并编译 Pikafish 引擎用于 Android (arm64-v8a, armeabi-v7a)
# 需要 Android NDK (r27c 或更新版本)
# ============================================================

param(
    [string]$NdkPath = "",
    [string]$Arch = "all"  # all, arm64, arm32
)

$ErrorActionPreference = "Stop"

# ============================================================
# 配置
# ============================================================
$PIKAFISH_REPO = "https://github.com/official-pikafish/Pikafish.git"
$PIKAFISH_BRANCH = "master"
$PROJECT_ROOT = Split-Path -Parent $PSScriptRoot
$BUILD_DIR = "$PROJECT_ROOT\build\pikafish"
$OUTPUT_DIR = "$PROJECT_ROOT\app\android\app\src\main\jniLibs"

# 查找 NDK
if (-not $NdkPath) {
    $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk"
    if (Test-Path "$sdkRoot\ndk") {
        $ndkVersions = Get-ChildItem "$sdkRoot\ndk" | Sort-Object Name -Descending
        if ($ndkVersions.Count -gt 0) {
            $NdkPath = $ndkVersions[0].FullName
        }
    }
    if (-not $NdkPath -and $env:ANDROID_NDK_HOME) {
        $NdkPath = $env:ANDROID_NDK_HOME
    }
}

if (-not $NdkPath -or -not (Test-Path $NdkPath)) {
    Write-Host "====================================================" -ForegroundColor Red
    Write-Host "  未找到 Android NDK！请先安装 NDK。" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "  安装方法（任选一种）：" -ForegroundColor Yellow
    Write-Host "  1. 通过 Android Studio -> SDK Manager -> SDK Tools" -ForegroundColor Yellow
    Write-Host "  2. 使用 sdkmanager：" -ForegroundColor Yellow

    $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk"
    Write-Host "     $sdkRoot\cmdline-tools\latest\bin\sdkmanager.bat 'ndk;27.2.12479018'" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Red
    Write-Host "  然后重新运行此脚本：" -ForegroundColor Yellow
    Write-Host "  .\scripts\build_pikafish.ps1" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Red
    exit 1
}

$NDK_TOOLCHAIN = "$NdkPath\toolchains\llvm\prebuilt\windows-x86_64"
if (-not (Test-Path $NDK_TOOLCHAIN)) {
    Write-Error "NDK toolchain 未找到: $NDK_TOOLCHAIN"
    exit 1
}

# 将NDK bin目录加入PATH
$env:Path = "$NDK_TOOLCHAIN\bin;$env:Path"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Pikafish Android 编译脚本" -ForegroundColor Cyan
Write-Host "  NDK: $NdkPath" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# ============================================================
# 克隆 Pikafish
# ============================================================
if (-not (Test-Path "$BUILD_DIR\Pikafish")) {
    Write-Host "`n>> 克隆 Pikafish 源码..." -ForegroundColor Green
    New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null
    git clone --depth 1 -b $PIKAFISH_BRANCH $PIKAFISH_REPO "$BUILD_DIR\Pikafish"
} else {
    Write-Host "`n>> Pikafish 源码已存在，跳过克隆" -ForegroundColor Yellow
}

# ============================================================
# 编译函数
# ============================================================
function Build-Pikafish {
    param(
        [string]$ArchName,
        [string]$MakeArch,
        [string]$OutputAbi
    )

    Write-Host "`n>> 编译 $ArchName ($MakeArch)..." -ForegroundColor Green

    $srcDir = "$BUILD_DIR\Pikafish\src"

    Push-Location $srcDir

    # 清理
    # 在 Windows 上使用 MSYS make (来自 Git 安装)
    $gitDir = Split-Path (Get-Command git).Source
    $usrBinDir = Join-Path (Split-Path $gitDir) "usr\bin"
    $makePath = Join-Path $usrBinDir "make.exe"

    if (-not (Test-Path $makePath)) {
        # 尝试直接用 make
        $makePath = "make"
    }

    # 使用 MSYS 环境编译
    $env:COMP = "ndk"

    try {
        & $makePath clean 2>$null
    } catch { }

    Write-Host "   使用 make: $makePath" -ForegroundColor Gray
    Write-Host "   ARCH=$MakeArch COMP=ndk" -ForegroundColor Gray

    & $makePath -j$([Environment]::ProcessorCount) build ARCH=$MakeArch COMP=ndk 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "   编译失败！尝试使用 WSL..." -ForegroundColor Yellow
        # 备选：检查WSL是否可用
        $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
        if ($wslAvailable) {
            $wslSrcDir = wsl wslpath -u "$srcDir"
            wsl bash -c "cd '$wslSrcDir' && make clean && make -j$(nproc) build ARCH=$MakeArch COMP=ndk"
        } else {
            Pop-Location
            Write-Error "编译 $ArchName 失败"
            return
        }
    }

    Pop-Location

    # 复制输出文件
    $outputDir = "$OUTPUT_DIR\$OutputAbi"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    $exeName = "pikafish"
    if (Test-Path "$srcDir\$exeName") {
        Copy-Item "$srcDir\$exeName" "$outputDir\libpikafish.so" -Force
        Write-Host "   >> 输出: $outputDir\libpikafish.so" -ForegroundColor Green
    } else {
        Write-Host "   未找到编译输出文件 $srcDir\$exeName" -ForegroundColor Red
    }
}

# ============================================================
# 执行编译
# ============================================================

if ($Arch -eq "all" -or $Arch -eq "arm64") {
    Build-Pikafish -ArchName "ARM64" -MakeArch "armv8" -OutputAbi "arm64-v8a"
}

if ($Arch -eq "all" -or $Arch -eq "arm32") {
    Build-Pikafish -ArchName "ARM32" -MakeArch "armv7" -OutputAbi "armeabi-v7a"
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "  编译完成！" -ForegroundColor Cyan
Write-Host "  输出目录: $OUTPUT_DIR" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
