; =============================================================================
; 番茄端碗 (FanqieDuanwan) Windows 桌面版安装包 (Inno Setup 6)
; 由 CI 打包。关键路径用 ISCC 命令行 /D 以绝对路径传入，避免相对路径歧义:
;   {#AppSourceDir} = <repo>\build\windows\x64\runner\Release   (flutter build 产物)
;   {#LangDir}      = <repo>\windows\languages                  (本地中文语言文件)
;   {#VcRedist}     = vc_redist.x64.exe 绝对路径（media_kit 自带 libmpv 依赖
;                     VC++ 2015-2022 运行库；CI 未传该定义时自动跳过）
; 版本号: CI 打包前把 "#define MyAppVersion" 替换成 pubspec.yaml 的版本。
; 输出:   installer-out\fanqieduanwan-setup-x64.exe
;
; 视觉：向导左侧 164x314 品牌图与右上角 55x55 小图由
; scripts/generate_brand_assets.py 生成，改图请重跑该脚本，不要手改 BMP。
; =============================================================================

#ifndef MyAppVersion
#define MyAppVersion "1.1.0"
#endif

[Setup]
; AppId 是升级身份，一旦发布不要改，否则新版本会被当成另一个软件安装。
; 这个值自 v1.1.0 发布起就是 liuguang-desktop-pc。改名只影响展示名与安装目录，
; 不改 AppId——否则 Windows 会把「番茄端碗」当成第二个软件并存安装，旧的还删不掉。
AppId=liuguang-desktop-pc
AppName=番茄端碗
AppVersion={#MyAppVersion}
AppVerName=番茄端碗 {#MyAppVersion}
AppPublisher=番茄端碗 (FanqieDuanwan)
AppPublisherURL=https://github.com/byazlle/winFQAPP
AppSupportURL=https://github.com/byazlle/winFQAPP/issues
AppUpdatesURL=https://github.com/byazlle/winFQAPP/releases
DefaultDirName={autopf}\FanqieDuanwan
DefaultGroupName=番茄端碗
OutputDir=installer-out
OutputBaseFilename=fanqieduanwan-setup-x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 路径相对 installer.iss 所在目录（windows\），故三项都从 windows\ 起算。
WizardImageFile=installer\wizard-large.bmp
WizardSmallImageFile=installer\wizard-small.bmp
WizardImageStretch=no
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\fanqieduanwan.exe
UninstallDisplayName=番茄端碗
PrivilegesRequired=admin
CreateUninstallRegKey=yes
SetupLogging=yes
; 单应用安装包不需要让用户选开始菜单文件夹，直接进安装页更利落。
DisableProgramGroupPage=yes
; 覆盖升级时先关掉正在运行的旧进程，避免“文件被占用”导致安装失败。
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinese"; MessagesFile: "{#LangDir}\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#AppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef VcRedist
; VC++ 2015-2022 运行库：media_kit 随包的 libmpv（MSVC 构建）在缺少运行库的
; 机器上会报“找不到 VCRUNTIME140.dll”。装到临时目录、装完即删。
Source: "{#VcRedist}"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
#endif

[Icons]
Name: "{group}\番茄端碗"; Filename: "{app}\fanqieduanwan.exe"
Name: "{group}\卸载 番茄端碗"; Filename: "{uninstallexe}"
Name: "{autodesktop}\番茄端碗"; Filename: "{app}\fanqieduanwan.exe"; Tasks: desktopicon

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
Filename: "{app}\fanqieduanwan.exe"; Description: "运行 番茄端碗"; Flags: nowait postinstall skipifsilent

; 卸载时彻底清除程序数据目录，避免章节缓存 / 离线剧集 / 历史等残留。
; getApplicationSupportDirectory 在 Windows 返回 %APPDATA%\<CompanyName>\<ProductName>，
; 现名 byazlle\FanqieDuanwan；旧品牌 fqapp 的两个历史位置一并清掉，避免升级后留垃圾。
[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\byazlle\FanqieDuanwan"
Type: filesandordirs; Name: "{userappdata}\fqapp"
Type: filesandordirs; Name: "{userappdata}\com.example\fqapp"
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
