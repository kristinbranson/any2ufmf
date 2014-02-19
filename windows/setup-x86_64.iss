#define AppVer GetFileVersion('x64\Release\any2ufmf.exe')

[Setup]
AppName=any2ufmf
AppVersion={#AppVer}
SourceDir=x64\Release
OutputDir=..\..\installers
OutputBaseFilename=any2ufmf-{#AppVer}-installer-x86_64
DefaultDirName={pf}\any2ufmf
DefaultGroupName=any2ufmf
DisableProgramGroupPage=yes
AlwaysShowGroupOnReadyPage=yes
PrivilegesRequired=none
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "any2ufmf.exe"; DestDir: "{app}"
Source: "*.dll"; DestDir: "{app}"

[Icons]
Name: "{group}\any2ufmf"; Filename: "{app}\any2ufmf.exe";
Name: "{userdesktop}\any2ufmf"; Filename: "{app}\any2ufmf.exe";
