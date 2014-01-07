[Setup]
AppName=any2ufmf
AppVersion=1.0
SourceDir=x64\Release
OutputDir=..\..
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
Name: "{userdesktop}\any2ufmf"; Filename: "{app}\any2ufme.exe";
