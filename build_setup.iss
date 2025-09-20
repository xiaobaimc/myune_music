[Setup]
AppName=MyuneMusic
AppVersion=0.6.5
AppPublisher=Myune
DefaultDirName={autopf}\MyuneMusic
DefaultGroupName=MyuneMusic
OutputBaseFilename=MyuneMusic_v0.6.5_setup_windows-x64
Compression=lzma
SolidCompression=yes
OutputDir=output_setup
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayName=MyuneMusic

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.01

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MyuneMusic"; Filename: "{app}\myune_music.exe"
Name: "{group}\{cm:UninstallProgram,MyuneMusic}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MyuneMusic"; Filename: "{app}\myune_music.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\MyuneMusic"; Filename: "{app}\myune_music.exe"; Tasks: quicklaunchicon; OnlyBelowVersion: 6.01

[Run]
Filename: "{app}\myune_music.exe"; Description: "{cm:LaunchProgram,MyuneMusic}"; Flags: nowait postinstall skipifsilent