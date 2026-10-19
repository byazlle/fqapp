<#
  Windows 构建脚本 (云端 CI 与本地 Windows 共用)
  --------------------------------------------------------------------------
  职责:
    1. (可选, 非致命) 生成 flutter_rust_bridge 绑定。仓库已提交绑定
       (lib/src/rust/frb_generated.dart + rust/src/frb_generated.rs),
       若 codegen 可用则刷新, 失败则回退到已提交绑定, 不阻断构建。
    2. 编译 Rust 核心为 Windows cdylib -> liuguang_core.dll  (不依赖 Android NDK)
    3. 生成 Flutter Windows 运行器 (若缺失) 并构建 release/debug
    4. 将 liuguang_core.dll 放到 FRB 期望的位置:
         <Release>/liuguang_core.dll                        (兜底)
         <Release>/rust/target/release/liuguang_core.dll    (匹配 frb ioDirectory)

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
# 1) FRB codegen (非致命: 失败则用仓库已提交的绑定)
# --------------------------------------------------------------------------
try {
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
    Write-Host '==> codegen OK'
}
catch {
    Write-Warning "codegen failed, using committed bindings. detail: $_"
}

# --------------------------------------------------------------------------
# 2) Rust core cdylib (Windows MSVC, no NDK)
# --------------------------------------------------------------------------
Write-Host '==> building liuguang_core cdylib (x86_64-pc-windows-msvc) ...'
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

$DllSrc = Join-Path $AppDir "rust/target/$CargoProfile/liuguang_core.dll"
if (-not (Test-Path -LiteralPath $DllSrc)) {
    throw "liuguang_core.dll not found at $DllSrc"
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
# 4) place the native core where FRB expects it
#    frb_generated.dart: ExternalLibraryLoaderConfig(stem:'liuguang_core',
#      ioDirectory:'rust/target/release/')  -> 相对 exe 目录解析
# --------------------------------------------------------------------------
$DllDst = Join-Path $AppDir "build/windows/x64/runner/$FlutterOut"
if (-not (Test-Path -LiteralPath $DllDst)) {
    throw "Flutter output dir not found: $DllDst"
}
# (a) 兜底: exe 同目录
Copy-Item -Force -LiteralPath $DllSrc -Destination $DllDst
# (b) 匹配 FRB ioDirectory: <Release>/rust/target/release/
$DllDstIo = Join-Path $DllDst 'rust/target/release'
New-Item -ItemType Directory -Path $DllDstIo -Force | Out-Null
Copy-Item -Force -LiteralPath $DllSrc -Destination $DllDstIo
Write-Host "==> copied liuguang_core.dll -> $DllDst and $DllDstIo"

Write-Host 'BUILD DONE'
