; =============================================================================
; fqapp Windows 桌面版安装包 (Inno Setup 6)
; 由 CI 在打包前把 "#define MyAppVersion" 的版本号替换成 pubspec.yaml 里的版本。
; 输入目录: build\windows\x64\runner\Release\  (flututer build windows 产物)
; 输出:     installer-out\fqapp-setup-x64.exe
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
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\fqapp"; Filename: "{app}\fqapp.exe"
Name: "{autodesktop}\fqapp"; Filename: "{app}\fqapp.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"

[Run]
Filename: "{app}\fqapp.exe"; Description: "运行 fqapp"; Flags: nowait postinstall skipifsilent
