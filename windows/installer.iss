; =============================================================================
; fqapp Windows 桌面版安装包 (Inno Setup 6)
; 由 CI 打包。关键路径用 ISCC 命令行 /D 以绝对路径传入，避免相对路径歧义:
;   {#AppSourceDir} = <repo>\build\windows\x64\runner\Release   (flutter build 产物)
;   {#LangDir}      = <repo>\windows\languages                  (本地中文语言文件)
;   {#VcRedist}     = vc_redist.x64.exe 绝对路径（media_kit 自带 libmpv 依赖
;                     VC++ 2015-2022 运行库；CI 未传该定义时自动跳过）
; 版本号: CI 打包前把 "#define MyAppVersion" 替换成 pubspec.yaml 的版本。
; 输出:   installer-out\fqapp-setup-x64.exe
; =============================================================================

#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif

[Setup]
AppId=fqapp-desktop-pc
AppName=fqapp
AppVersion={#MyAppVersion}
AppPublisher=fqapp (GPL-3.0)
DefaultDirName={autopf}\fqapp
DefaultGroupName=fqapp
OutputDir=installer-out
OutputBaseFilename=fqapp-setup-x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayName=fqapp
CreateUninstallRegKey=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinese"; MessagesFile: "{#LangDir}\ChineseSimplified.isl"

[Files]
Source: "{#AppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef VcRedist
; VC++ 2015-2022 运行库：media_kit 随包的 libmpv（MSVC 构建）在缺少运行库的
; 机器上会报“找不到 VCRUNTIME140.dll”。装到临时目录、装完即删。
Source: "{#VcRedist}"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
#endif

[Icons]
Name: "{group}\fqapp"; Filename: "{app}\fqapp.exe"
Name: "{autodesktop}\fqapp"; Filename: "{app}\fqapp.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"

[Run]
#ifdef VcRedist
; 始终安装/修复 VC++ 2015-2022 运行库（media_kit 随包的 libmpv 为 MSVC 构建，
; 依赖 VCRUNTIME140 / MSVCP140 及其 _1 变体）。仅按注册表键判断“已安装”会漏掉
; 已损坏或只装了旧版（如 2015-2019，缺 _1 变体）的运行库，导致 libmpv 加载失败、
; 视频无法播放而其余功能正常。改为始终静默安装/修复，幂等且安全。
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "正在安装 Visual C++ 运行库..."
#endif
Filename: "{app}\fqapp.exe"; Description: "运行 fqapp"; Flags: nowait postinstall skipifsilent

; 卸载时彻底清除程序数据目录，避免章节缓存 / 离线剧集 / 历史等残留。
; getApplicationSupportDirectory 在 Windows 指向 %APPDATA%\fqapp（Roaming），
; 海报缓存等落在 %LOCALAPPDATA%\fqapp（Local），两者都删。
[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\fqapp"
Type: filesandordirs; Name: "{localappdata}\fqapp"

[Code]
function VCRedistInstalled: Boolean;
var
  installed: Cardinal;
begin
  // VC++ 2015-2022（x64）安装后写下这个键值；缺键或为 0 视为未安装。
  installed := 0;
  Result :=
      RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', installed)
      and (installed = 1);
end;
