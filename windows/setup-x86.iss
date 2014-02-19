#define AppVer GetFileVersion('Win32\Release\any2ufmf.exe')

[Setup]
AppName=any2ufmf
AppVersion={#AppVer}
SourceDir=Win32\Release
OutputDir=..\..\installers
OutputBaseFilename=any2ufmf-{#AppVer}-installer-x86
DefaultDirName={pf}\any2ufmf
DefaultGroupName=any2ufmf
DisableProgramGroupPage=yes
AlwaysShowGroupOnReadyPage=yes
PrivilegesRequired=none

[Files]
Source: "any2ufmf.exe"; DestDir: "{app}"
Source: "*.dll"; DestDir: "{app}"

[Icons]
Name: "{group}\any2ufmf"; Filename: "{app}\any2ufmf.exe";
Name: "{userdesktop}\any2ufmf"; Filename: "{app}\any2ufmf.exe";
