#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef AppBuild
  #define AppBuild "12"
#endif

#ifdef UpdateTestMode
  #ifndef UpdateInnoAppId
    #error UpdateInnoAppId is required in UpdateTestMode
  #endif
  #if UpdateInnoAppId != "8B18F7D4-35F6-4DDE-ABFD-E76991B831D2"
    #error UpdateInnoAppId must be the isolated Equis update test AppId
  #endif
  #ifndef UpdateReleaseRoot
    #error UpdateReleaseRoot is required in UpdateTestMode
  #endif
  #ifndef UpdateOutputDir
    #error UpdateOutputDir is required in UpdateTestMode
  #endif
  #ifndef UpdateInstallRoot
    #error UpdateInstallRoot is required in UpdateTestMode
  #endif
  #define AppName "Equis Update Test"
  #define BuildRoot UpdateReleaseRoot
#else
  #ifdef UpdateInnoAppId
    #error UpdateInnoAppId requires UpdateTestMode
  #endif
  #ifdef UpdateReleaseRoot
    #error UpdateReleaseRoot requires UpdateTestMode
  #endif
  #ifdef UpdateOutputDir
    #error UpdateOutputDir requires UpdateTestMode
  #endif
  #ifdef UpdateInstallRoot
    #error UpdateInstallRoot requires UpdateTestMode
  #endif
  #define AppName "Equis"
  #define BuildRoot "..\build\windows\x64\runner\Release"
#endif
#define AppPublisher "Equis"
#define AppExeName "equis.exe"

[Setup]
#ifdef UpdateTestMode
AppId={{{#UpdateInnoAppId}}
#else
AppId={{B9ECD233-7990-478B-A5F1-C30E4BCAA15E}
#endif
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
#ifdef UpdateTestMode
DefaultDirName={#UpdateInstallRoot}
#else
DefaultDirName={localappdata}\Programs\{#AppName}
#endif
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
#ifdef UpdateTestMode
OutputDir={#UpdateOutputDir}
#else
OutputDir=..\dist
#endif
OutputBaseFilename=Equis-Windows-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}.{#AppBuild}
#ifdef ReleaseSigned
SignTool=release
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[CustomMessages]
english.ManagedUpdateDirRequired=Managed updates require exactly one /DIR= target directory.
brazilianportuguese.ManagedUpdateDirRequired=Atualizações gerenciadas exigem exatamente um diretório de destino /DIR=.
english.ManagedUpdateDirChanged=The installation directory was changed. Restart the update to install into its existing directory.
brazilianportuguese.ManagedUpdateDirChanged=O diretório de instalação foi alterado. Reinicie a atualização para instalar no diretório existente.
english.ManagedUpdateInvalidRequest=The managed update request is invalid. Restart the update.
brazilianportuguese.ManagedUpdateInvalidRequest=A solicitação de atualização gerenciada é inválida. Reinicie a atualização.
english.ManagedUpdateHandshakeFailed=The update could not be authorized by the running application. Restart the update.
brazilianportuguese.ManagedUpdateHandshakeFailed=A atualização não foi autorizada pelo aplicativo em execução. Reinicie a atualização.

[Files]
Source: "{#BuildRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; Check: not IsManagedUpdate

[Code]
type
  HANDLE = THandle;
  TUpdateOverlapped = record
    InternalValue: INT_PTR;
    InternalHigh: INT_PTR;
    Offset: DWORD;
    OffsetHigh: DWORD;
    EventHandle: HANDLE;
  end;

function UpdateCreateFile(Name: String; Access, ShareMode: DWORD;
  Security: INT_PTR; Creation, Flags: DWORD; Template: HANDLE): HANDLE;
  external 'CreateFileW@kernel32.dll stdcall';
function UpdateWaitNamedPipe(Name: String; Timeout: DWORD): BOOL;
  external 'WaitNamedPipeW@kernel32.dll stdcall';
function UpdateCreateEvent(Security: INT_PTR; ManualReset, InitialState: BOOL;
  Name: INT_PTR): HANDLE;
  external 'CreateEventW@kernel32.dll stdcall';
function UpdateReadFile(Handle: HANDLE; var Buffer: Byte; Count: DWORD;
  var Transferred: DWORD; var Overlapped: TUpdateOverlapped): BOOL;
  external 'ReadFile@kernel32.dll stdcall';
function UpdateWriteFile(Handle: HANDLE; var Buffer: Byte; Count: DWORD;
  var Transferred: DWORD; var Overlapped: TUpdateOverlapped): BOOL;
  external 'WriteFile@kernel32.dll stdcall';
function UpdateGetOverlappedResult(Handle: HANDLE;
  var Overlapped: TUpdateOverlapped; var Transferred: DWORD;
  Wait: BOOL): BOOL;
  external 'GetOverlappedResult@kernel32.dll stdcall';
function UpdateCancelIoEx(Handle: HANDLE;
  var Overlapped: TUpdateOverlapped): BOOL;
  external 'CancelIoEx@kernel32.dll stdcall';
function UpdateWaitForSingleObject(Handle: HANDLE; Timeout: DWORD): DWORD;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function UpdateCloseHandle(Handle: HANDLE): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';
function UpdateGetTickCount64: Int64;
  external 'GetTickCount64@kernel32.dll stdcall';
function UpdateGetLastError: DWORD;
  external 'GetLastError@kernel32.dll stdcall';

var
  UpdateAttemptUsed: Boolean;

function IsManagedUpdate: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    if CompareText(ParamStr(I), '/EQUISMANAGEDUPDATE') = 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function IsLowerHexTransaction(Value: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(Value) <> 32 then
    Exit;
  for I := 1 to 32 do
    if not (((Value[I] >= '0') and (Value[I] <= '9')) or
            ((Value[I] >= 'a') and (Value[I] <= 'f'))) then
      Exit;
  Result := True;
end;

procedure InitializeWizard;
begin
  if IsManagedUpdate then
  begin
    WizardForm.DirEdit.Enabled := False;
    WizardForm.DirBrowseButton.Enabled := False;
  end;
end;

procedure TransferUpdateByte(Handle: HANDLE; var Value: Byte;
  WriteValue: Boolean; Deadline: Int64);
var
  EventHandle: HANDLE;
  Overlapped: TUpdateOverlapped;
  Transferred, LastError, WaitResult, Remaining: DWORD;
  Pending: Boolean;
begin
  EventHandle := UpdateCreateEvent(0, True, False, 0);
  if EventHandle = 0 then
    RaiseException('Update pipe event could not be created');
  try
    Overlapped.InternalValue := 0;
    Overlapped.InternalHigh := 0;
    Overlapped.Offset := 0;
    Overlapped.OffsetHigh := 0;
    Overlapped.EventHandle := EventHandle;
    Transferred := 0;
    if WriteValue then
      Pending := not UpdateWriteFile(Handle, Value, 1, Transferred, Overlapped)
    else
      Pending := not UpdateReadFile(Handle, Value, 1, Transferred, Overlapped);
    if Pending then
    begin
      LastError := UpdateGetLastError;
      if LastError <> 997 then
        RaiseException('Update pipe I/O failed');
      if UpdateGetTickCount64 >= Deadline then
        Remaining := 0
      else
        Remaining := DWORD(Deadline - UpdateGetTickCount64);
      WaitResult := UpdateWaitForSingleObject(EventHandle, Remaining);
      if WaitResult <> 0 then
      begin
        UpdateCancelIoEx(Handle, Overlapped);
        { The kernel may still own both the record and Value after cancellation. }
        UpdateGetOverlappedResult(Handle, Overlapped, Transferred, True);
        RaiseException('Update pipe timed out');
      end;
      if not UpdateGetOverlappedResult(Handle, Overlapped, Transferred, True) then
        RaiseException('Update pipe I/O failed');
    end;
    if Transferred <> 1 then
      RaiseException('Update pipe closed unexpectedly');
  finally
    UpdateCloseHandle(EventHandle);
  end;
end;

procedure WriteUpdateLine(Handle: HANDLE; Text: String; Deadline: Int64);
var
  Encoded: AnsiString;
  Value: Byte;
  I: Integer;
begin
  Encoded := Utf8Encode(Text + #10);
  if Length(Encoded) > 8192 then
    RaiseException('Update request is too long');
  for I := 1 to Length(Encoded) do
  begin
    Value := Ord(Encoded[I]);
    TransferUpdateByte(Handle, Value, True, Deadline);
  end;
end;

function ReadUpdateLine(Handle: HANDLE; Deadline: Int64): String;
var
  Value: Byte;
  I: Integer;
begin
  Result := '';
  for I := 1 to 8192 do
  begin
    Value := 0;
    TransferUpdateByte(Handle, Value, False, Deadline);
    if Value = 10 then
      Exit;
    if ((Value < 32) and (Value <> 9)) or (Value > 126) then
      RaiseException('Invalid update response');
    Result := Result + Chr(Value);
  end;
  RaiseException('Update response is too long');
end;

function RequestUpdateGo(PipeName, Transaction, Hive: String): Boolean;
var
  Handle: HANDLE;
  Response, Request: String;
  Deadline: Int64;
begin
  Result := False;
  Handle := UpdateCreateFile(PipeName, $C0000000, 0, 0, 3, $40110000, 0);
  if (Handle = -1) and (UpdateGetLastError = 231) then
  begin
    if UpdateWaitNamedPipe(PipeName, 30000) then
      Handle := UpdateCreateFile(PipeName, $C0000000, 0, 0, 3, $40110000, 0);
  end;
  if Handle = -1 then
    Exit;
  try
    Deadline := UpdateGetTickCount64 + 30000;
    Request := 'EQUIS_UPDATE_2' + #9 + 'INSTALL_REQUEST' + #9 +
      Transaction + #9 + Hive + #9 + '{#AppVersion}' + #9 +
      '{#AppBuild}' + #9 + WizardDirValue;
    WriteUpdateLine(Handle, Request, Deadline);
    { Closing the workspace may take 120 seconds, plus the response exchange. }
    Deadline := UpdateGetTickCount64 + 150000;
    Response := ReadUpdateLine(Handle, Deadline);
    Result := Response = ('EQUIS_UPDATE_2' + #9 + 'GO' + #9 + Transaction);
  finally
    UpdateCloseHandle(Handle);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  I, ManagedCount, TransactionCount, PipeCount, DirCount, ModeCount,
    NoCloseCount, NoForceCount, NoRestartAppsCount, NoRestartCount: Integer;
  Argument, RequestedDir, Transaction, PipeName, Hive: String;
  Invalid: Boolean;
begin
  Result := '';
  if not IsManagedUpdate then
    Exit;
  if UpdateAttemptUsed then
  begin
    Result := CustomMessage('ManagedUpdateHandshakeFailed');
    Exit;
  end;
  UpdateAttemptUsed := True;

  ManagedCount := 0;
  TransactionCount := 0;
  PipeCount := 0;
  DirCount := 0;
  ModeCount := 0;
  NoCloseCount := 0;
  NoForceCount := 0;
  NoRestartAppsCount := 0;
  NoRestartCount := 0;
  Invalid := False;
  Transaction := '';
  PipeName := '';
  RequestedDir := '';
  Hive := '';
  for I := 1 to ParamCount do
  begin
    Argument := ParamStr(I);
    if CompareText(Copy(Argument, 1, 5), '/DIR=') = 0 then
    begin
      DirCount := DirCount + 1;
      RequestedDir := Copy(Argument, 6, Length(Argument) - 5);
    end
    else if CompareText(Argument, '/EQUISMANAGEDUPDATE') = 0 then
      ManagedCount := ManagedCount + 1
    else if CompareText(Copy(Argument, 1, Length('/EQUISTRANSACTION=')),
                        '/EQUISTRANSACTION=') = 0 then
    begin
      TransactionCount := TransactionCount + 1;
      Transaction := Copy(Argument, Length('/EQUISTRANSACTION=') + 1,
                          Length(Argument));
    end
    else if CompareText(Copy(Argument, 1, Length('/EQUISPIPE=')),
                        '/EQUISPIPE=') = 0 then
    begin
      PipeCount := PipeCount + 1;
      PipeName := Copy(Argument, Length('/EQUISPIPE=') + 1,
                       Length(Argument));
    end
    else if CompareText(Argument, '/CURRENTUSER') = 0 then
    begin
      ModeCount := ModeCount + 1;
      Hive := 'HKCU';
    end
    else if CompareText(Argument, '/ALLUSERS') = 0 then
    begin
      ModeCount := ModeCount + 1;
      Hive := 'HKLM';
    end
    else if CompareText(Argument, '/NOCLOSEAPPLICATIONS') = 0 then
      NoCloseCount := NoCloseCount + 1
    else if CompareText(Argument, '/NOFORCECLOSEAPPLICATIONS') = 0 then
      NoForceCount := NoForceCount + 1
    else if CompareText(Argument, '/NORESTARTAPPLICATIONS') = 0 then
      NoRestartAppsCount := NoRestartAppsCount + 1
    else if CompareText(Argument, '/NORESTART') = 0 then
      NoRestartCount := NoRestartCount + 1
    else if (CompareText(Argument, '/CLOSEAPPLICATIONS') = 0) or
            (CompareText(Argument, '/FORCECLOSEAPPLICATIONS') = 0) or
            (CompareText(Argument, '/RESTARTAPPLICATIONS') = 0) or
            (CompareText(Argument, '/SILENT') = 0) or
            (CompareText(Argument, '/VERYSILENT') = 0) then
      Invalid := True;
  end;

  if (DirCount <> 1) or (RequestedDir = '') then
  begin
    Result := CustomMessage('ManagedUpdateDirRequired');
    Exit;
  end;

  if (ManagedCount <> 1) or (TransactionCount <> 1) or
     (PipeCount <> 1) or (ModeCount <> 1) or
     (NoCloseCount <> 1) or (NoForceCount <> 1) or
     (NoRestartAppsCount <> 1) or (NoRestartCount <> 1) or
     Invalid or (not IsLowerHexTransaction(Transaction)) or
     (PipeName <> ('\\.\pipe\Equis.Update.' + Transaction)) or
     ((Hive = 'HKLM') <> IsAdminInstallMode) then
  begin
    Result := CustomMessage('ManagedUpdateInvalidRequest');
    Exit;
  end;

  if CompareText(RemoveBackslashUnlessRoot(RequestedDir),
                 RemoveBackslashUnlessRoot(WizardDirValue)) <> 0 then
  begin
    Result := CustomMessage('ManagedUpdateDirChanged');
    Exit;
  end;

  try
    if not RequestUpdateGo(PipeName, Transaction, Hive) then
      Result := CustomMessage('ManagedUpdateHandshakeFailed');
  except
    Result := CustomMessage('ManagedUpdateHandshakeFailed');
  end;
end;
