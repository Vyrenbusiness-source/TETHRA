; TETHRA Windows-Installer (Inno Setup 6).
; Bauen: ISCC.exe /DSrc=<Ordner mit TETHRA.exe, TETHRA.pck, TETHRA_worlds.pck, maps\, tools\> /DAppVer=1.14.3 tools\installer\tethra.iss
; Installiert pro Nutzer (ohne Admin) nach %LOCALAPPDATA%\Programs\TETHRA,
; damit der eingebaute Updater TETHRA.pck neben der exe ersetzen darf.

#ifndef Src
  #error "Src fehlt: /DSrc=<Staging-Ordner>"
#endif
#ifndef AppVer
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{6E2B7C41-3F7A-4C1E-9B7D-5A1E7C0F7E21}
AppName=TETHRA
AppVersion={#AppVer}
AppVerName=TETHRA {#AppVer}
AppPublisher=Vyrenbusiness-source
AppPublisherURL=https://github.com/Vyrenbusiness-source/TETHRA
AppSupportURL=https://github.com/Vyrenbusiness-source/TETHRA/issues
DefaultDirName={autopf}\TETHRA
DefaultGroupName=TETHRA
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=TETHRA_Setup
OutputDir={#SourcePath}\..\..\release
SetupIconFile={#SourcePath}\tethra.ico
UninstallDisplayIcon={app}\TETHRA.exe
; Die Pakete sind schon komprimiert (WebP/OGG): schnelle Kompression reicht.
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Src}\TETHRA.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\TETHRA.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\TETHRA_worlds.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\TETHRA Kompatibilitaetsmodus.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\README.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
; ffmpeg (GPL v3, gyan.dev "essentials") nur fuer Clip -> MP4; Lizenz in licenses\.
Source: "{#Src}\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#Src}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist
Source: "{#Src}\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs
; Beispiel-Maps: nie ueberschreiben (Nutzer kann sie geloescht oder ersetzt haben).
Source: "{#Src}\maps\*"; DestDir: "{app}\maps"; Flags: onlyifdoesntexist recursesubdirs

[Icons]
Name: "{autoprograms}\TETHRA"; Filename: "{app}\TETHRA.exe"
Name: "{autoprograms}\TETHRA (Kompatibilitätsmodus)"; Filename: "{app}\TETHRA Kompatibilitaetsmodus.bat"; IconFilename: "{app}\TETHRA.exe"
Name: "{autodesktop}\TETHRA"; Filename: "{app}\TETHRA.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TETHRA.exe"; Description: "{cm:LaunchProgram,TETHRA}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Vom Updater angelegte Dateien neben der exe.
Type: files; Name: "{app}\*.new"
Type: files; Name: "{app}\*.old"
