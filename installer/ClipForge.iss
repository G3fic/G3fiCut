#define MyAppName "ClipForge"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif
#define MyAppPublisher "ClipForge"
#define MyAppExeName "clipforge.exe"

[Setup]
AppId={{6B7F4C9D-21C3-4E88-9B13-CE9A4C1F6D27}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ClipForge
DefaultGroupName=ClipForge
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\build\installer
OutputBaseFilename=ClipForge-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ClipForge"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\ClipForge"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить ClipForge"; Flags: postinstall nowait
