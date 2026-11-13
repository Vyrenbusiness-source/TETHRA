; OMEN Windows-Installer (Inno Setup 6).
; Bauen (PowerShell, nicht Git Bash): ISCC.exe /DSrc=<Ordner mit OMEN.exe, OMEN.pck, OMEN_worlds.pck, maps\, tools\> /DAppVer=1.36.0 tools\installer\omen.iss
; Installiert pro Nutzer (ohne Admin) nach %LOCALAPPDATA%\Programs\OMEN,
; damit der eingebaute Updater OMEN.pck neben der exe ersetzen darf.
;
; Das Spiel hiess bis v1.35.0 TETHRA. Die AppId ist dieselbe geblieben: dieses Setup
; aktualisiert eine bestehende TETHRA-Installation an ihrem Ort (Ordner bleibt, auch
; wenn er "TETHRA" heisst), loescht TETHRA.exe/TETHRA.pck und die alten Verknuepfungen
; und benennt ein vorhandenes TETHRA_worlds.pck um, statt 820 MB neu zu kopieren.
; Nutzerdaten liegen unveraendert unter %APPDATA%\Godot\app_userdata\TETHRA.

#ifndef Src
  #error "Src fehlt: /DSrc=<Staging-Ordner>"
#endif
#ifndef AppVer
  #define AppVer "1.0.0"
#endif
; Groesse des Welten-Pakets im Setup: ist lokal schon eins mit genau dieser Groesse da, wird es nicht neu kopiert.
#define WorldsSize FileSize(Src + "\OMEN_worlds.pck")
#if WorldsSize < 0
  #error "OMEN_worlds.pck fehlt im Staging-Ordner"
#endif

[Setup]
; Historische Kennung: NICHT aendern, sonst gilt das Setup als neues Programm (zweite Installation statt Upgrade).
AppId={{6E2B7C41-3F7A-4C1E-9B7D-5A1E7C0F7E21}
AppName=OMEN
AppVersion={#AppVer}
AppVerName=OMEN {#AppVer}
AppPublisher=Vyrenbusiness-source
AppPublisherURL=https://github.com/Vyrenbusiness-source/OMEN
AppSupportURL=https://github.com/Vyrenbusiness-source/OMEN/issues
; Neuinstallation: Ordner OMEN. Upgrade: der bisherige Ordner (UsePreviousAppDir).
DefaultDirName={autopf}\OMEN
UsePreviousAppDir=yes
DefaultGroupName=OMEN
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=OMEN_Setup
OutputDir={#SourcePath}\..\..\release
SetupIconFile={#SourcePath}\omen.ico
UninstallDisplayIcon={app}\OMEN.exe
; Die Pakete sind schon komprimiert (WebP/OGG): schnelle Kompression reicht.
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
en.GameRunning=The game is still running. Close it, then click Install again.
de.GameRunning=Das Spiel läuft noch. Bitte schließen und dann erneut auf Installieren klicken.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Reste der Installation unter dem alten Namen (bis v1.35.0).
Type: files; Name: "{app}\TETHRA.exe"
Type: files; Name: "{app}\TETHRA.pck"
Type: files; Name: "{app}\TETHRA.pck.new"
Type: files; Name: "{app}\TETHRA*.part"
Type: files; Name: "{app}\TETHRA Kompatibilitaetsmodus.bat"
Type: files; Name: "{app}\tethra_update.bat"
Type: files; Name: "{autoprograms}\TETHRA.lnk"
Type: files; Name: "{autoprograms}\TETHRA (Kompatibilit*).lnk"
Type: files; Name: "{autodesktop}\TETHRA.lnk"

[Files]
Source: "{#Src}\OMEN.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\OMEN.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\OMEN_worlds.pck"; DestDir: "{app}"; Flags: ignoreversion; Check: WorldsNeeded
Source: "{#Src}\OMEN Kompatibilitaetsmodus.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Src}\README.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
; ffmpeg (GPL v3, gyan.dev "essentials") nur fuer Clip -> MP4; Lizenz in licenses\.
Source: "{#Src}\ffmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#Src}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist
Source: "{#Src}\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs
; Beispiel-Maps: nie ueberschreiben (Nutzer kann sie geloescht oder ersetzt haben).
Source: "{#Src}\maps\*"; DestDir: "{app}\maps"; Flags: onlyifdoesntexist recursesubdirs

[Icons]
Name: "{autoprograms}\OMEN"; Filename: "{app}\OMEN.exe"
Name: "{autoprograms}\OMEN (Kompatibilitätsmodus)"; Filename: "{app}\OMEN Kompatibilitaetsmodus.bat"; IconFilename: "{app}\OMEN.exe"
Name: "{autodesktop}\OMEN"; Filename: "{app}\OMEN.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\OMEN.exe"; Description: "{cm:LaunchProgram,OMEN}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Vom Updater angelegte Dateien neben der exe.
Type: files; Name: "{app}\*.new"
Type: files; Name: "{app}\*.old"
Type: files; Name: "{app}\*.part"
; Welten-Paket: beim Upgrade nur umbenannt (nicht vom Setup kopiert) oder vom Updater geladen.
Type: files; Name: "{app}\OMEN_worlds.pck"
Type: files; Name: "{app}\TETHRA_worlds.pck"

[Code]
// Laeuft die Exe noch? Eine laufende Exe laesst sich nicht zum Schreiben oeffnen.
function ExeLocked(const Path: String): Boolean;
var
  S: TFileStream;
begin
  Result := False;
  if not FileExists(Path) then
    Exit;
  try
    S := TFileStream.Create(Path, fmOpenReadWrite or fmShareExclusive);
    S.Free;
  except
    Result := True;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if ExeLocked(ExpandConstant('{app}\TETHRA.exe')) or ExeLocked(ExpandConstant('{app}\OMEN.exe')) then
    Result := CustomMessage('GameRunning');
end;

// Upgrade einer TETHRA-Installation: Welten-Paket (820 MB) umbenennen statt neu kopieren.
procedure RenameOld(const OldName, NewName: String);
var
  O, N: String;
begin
  O := ExpandConstant('{app}\') + OldName;
  N := ExpandConstant('{app}\') + NewName;
  if FileExists(O) and not FileExists(N) then
    RenameFile(O, N);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    RenameOld('TETHRA_worlds.pck', 'OMEN_worlds.pck');
    RenameOld('TETHRA_worlds.pck.new', 'OMEN_worlds.pck.new');
  end;
  // Lagen beide Namen nebeneinander, bleibt nur das neue Paket.
  if (CurStep = ssPostInstall) and FileExists(ExpandConstant('{app}\OMEN_worlds.pck')) then
    DeleteFile(ExpandConstant('{app}\TETHRA_worlds.pck'));
end;

// Welten-Paket nur kopieren, wenn lokal keins mit der Groesse des Setups liegt.
function WorldsNeeded(): Boolean;
var
  Size: Integer;
  F: String;
begin
  Result := True;
  try
    F := ExpandConstant('{app}\OMEN_worlds.pck');
    Result := not (FileExists(F) and FileSize(F, Size) and (Size = {#WorldsSize}));
  except
    // {app} steht noch nicht fest (Aufruf vor der Ordnerwahl): kopieren.
  end;
end;
