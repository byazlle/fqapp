<#
  Windows 构建脚本 (云端 CI 与本地 Windows 共用)
  --------------------------------------------------------------------------
  职责:
    1. 生成 flutter_rust_bridge 绑定 (lib/src/rust + rust/src/bridge_generated.rs)
    2. 编译 Rust 核心为 Windows cdylib -> fqapi_core.dll  (不依赖 Android NDK)
    3. 生成 Flutter Windows 运行器 (若缺失) 并构建 release/debug
    4. 将 fqapi_core.dll 拷贝到可执行文件同目录 (FRB 在桌面端运行时动态加载)

  与 scripts/build_rust_backend.ps1 的区别:
    原脚本在 -HostLib 分支之前就硬校验 Android NDK，纯桌面构建被迫装 NDK。
    本脚本完全跳过 NDK，只产出桌面需要的 cdylib。

  用法:
    .\scripts\build_windows.ps1            # release
    .\scripts\build_windows.ps1 -Profile debug
#>

param(
    [ValidateSet('release', 'debug')][string]$Profile = 'release'
)

$ErrorActionPreference = 'Stop'
$AppDir = Split-Path -Parent $PSScriptRoot

# Flutter build 输出的目录名是大写 (Release / Debug)
$FlutterOut = if ($Profile -eq 'debug') { 'Debug' } else { 'Release' }
# Cargo 的 target 目录名是小写 (release / debug)
$CargoProfile = $Profile

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage (exit code $LASTEXITCODE)" }
}

# --------------------------------------------------------------------------
# 1) FRB codegen
# --------------------------------------------------------------------------
if (-not (Get-Command flutter_rust_bridge_codegen -ErrorAction SilentlyContinue)) {
    Write-Host '==> installing flutter_rust_bridge_codegen ...'
    Invoke-NativeCommand -Exe 'cargo' `
        -Arguments @('install', 'flutter_rust_bridge_codegen', '--version', '2.13.0', '--locked') `
        -FailureMessage 'cargo install flutter_rust_bridge_codegen failed'
}
Write-Host '==> generating flutter_rust_bridge bindings ...'
Push-Location -LiteralPath $AppDir
try {
    Invoke-NativeCommand -Exe 'flutter_rust_bridge_codegen' `
        -Arguments @('generate', '--config-file', 'flutter_rust_bridge.yaml') `
        -FailureMessage 'flutter_rust_bridge_codegen generate failed'
}
finally { Pop-Location }

# --------------------------------------------------------------------------
# 2) Rust core cdylib (Windows MSVC, no NDK)
# --------------------------------------------------------------------------
Write-Host '==> building fqapi_core cdylib (x86_64-pc-windows-msvc) ...'
rustup target add x86_64-pc-windows-msvc
Push-Location -LiteralPath (Join-Path $AppDir 'rust')
try {
    if ($Profile -eq 'debug') {
        Invoke-NativeCommand -Exe 'cargo' -Arguments @('build') -FailureMessage 'cargo build (debug) failed'
    }
    else {
        Invoke-NativeCommand -Exe 'cargo' -Arguments @('build', '--release') -FailureMessage 'cargo build (release) failed'
    }
}
finally { Pop-Location }

$DllSrc = Join-Path $AppDir "rust/target/$CargoProfile/fqapi_core.dll"
if (-not (Test-Path -LiteralPath $DllSrc)) {
    throw "fqapi_core.dll not found at $DllSrc"
}

# --------------------------------------------------------------------------
# 3) Flutter Windows runner + build
# --------------------------------------------------------------------------
flutter config --enable-windows-desktop | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $AppDir 'windows'))) {
    Write-Host '==> creating windows runner ...'
    Invoke-NativeCommand -Exe 'flutter' `
        -Arguments @('create', '--platforms=windows', '.') `
        -FailureMessage 'flutter create --platforms=windows failed'
}

Write-Host '==> flutter build windows ...'
Invoke-NativeCommand -Exe 'flutter' `
    -Arguments @('build', 'windows', "--$Profile") `
    -FailureMessage 'flutter build windows failed'

# --------------------------------------------------------------------------
# 4) place the native core next to the executable
# --------------------------------------------------------------------------
$DllDst = Join-Path $AppDir "build/windows/x64/runner/$FlutterOut"
if (-not (Test-Path -LiteralPath $DllDst)) {
    New-Item -ItemType Directory -Path $DllDst -Force | Out-Null
}
Copy-Item -Force -LiteralPath $DllSrc -Destination $DllDst
Write-Host "==> copied $DllSrc -> $DllDst"

Write-Host 'BUILD DONE'
