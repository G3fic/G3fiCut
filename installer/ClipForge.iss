#define MyAppName "G3fiCut"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif
#define MyAppPublisher "G3fiCut"
#define MyAppExeName "g3ficut.exe"

[Setup]
AppId={{6B7F4C9D-21C3-4E88-9B13-CE9A4C1F6D27}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\G3fiCut
DefaultGroupName=G3fiCut
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\build\installer
OutputBaseFilename=G3fiCut-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\G3fiCut"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\G3fiCut"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить G3fiCut"; Flags: postinstall nowait
