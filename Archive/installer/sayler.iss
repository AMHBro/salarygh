; مثبت تطبيق سايلر لحاسبة الزبون.
; يثبّت البرنامج في مجلد المستخدم وينشئ اختصاراً على سطح المكتب.

#define AppName "سايلر"
#define AppExe "sales_system.exe"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8F3A1C2E-6B47-4D19-9A55-7C2E4B91D0A6}
AppName={#AppName}
AppVersion=1.0.0
AppPublisher=iq.matrixit
DefaultDirName={localappdata}\Sayler
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=C:\Users\MASTER\Desktop
OutputBaseFilename=Sayler-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "تشغيل سايلر"; Flags: nowait postinstall skipifsilent
