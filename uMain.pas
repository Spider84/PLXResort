unit uMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ComCtrls, CommCtrl, TntComCtrls, StdCtrls, TntStdCtrls, ringbuffer,
  ExtCtrls, Menus, TntMenus, XPMan, JvComponentBase, JvLogFile, JvLogClasses,
  JvAppStorage, JvAppRegistryStorage, JvFormPlacement;

type
  TSensorData = record
    Addr:Word;
    Inst:Byte;
    Data:Word;
    units:Byte;
  end;

  TSensorDataShort = record
    Addr:Word;
    Inst:Byte;
    Data:Word;
  end;

  TParseThread = class(TThread)
    RingBuf: TSharedRingBuf;
    SyncData: Pointer;
    LastBuffer:TSharedRingBuf;

    FAddr:Word;
    FInst:Byte;
    FData:Word;

    FFreq:Word;

    FSensors:TList;
  private
    constructor Create(aBuf: TSharedRingBuf);
    destructor Destroy; override;
  protected
    procedure Execute; override;
    procedure DoPkt;
  end;

  TComThread = class(TThread)
    RingBuf: TSharedRingBuf;
    FComPort: THandle;
  private
    constructor Create(ComPort:THandle; aBuf: TSharedRingBuf);
  protected
    procedure Execute; override;
  end;

  TfmMain = class(TForm, IJvAppStorageHandler)
    lvSensors: TTntListView;
    cbbFromPORT: TTntComboBox;
    lblFromPORT: TTntLabel;
    lblEmulatePort: TTntLabel;
    cbbEmulatePORT: TTntComboBox;
    tntstsbr1: TTntStatusBar;
    tmrSend: TTimer;
    tntpmn1: TTntPopupMenu;
    tntmntmDisable: TTntMenuItem;
    tntmntmN1: TTntMenuItem;
    tmrLedOff: TTimer;
    tmrRedLedOff: TTimer;
    tmr1: TTimer;
    xpmnfst1: TXPManifest;
    jvlgfl1: TJvLogFile;
    jvprgstrystrg1: TJvAppRegistryStorage;
    jvfrmstrg1: TJvFormStorage;
    procedure FormCreate(Sender: TObject);
    procedure tmrSendTimer(Sender: TObject);
    procedure lvSensorsCompare(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
    procedure cbbFromPORTChange(Sender: TObject);
    procedure cbbEmulatePORTChange(Sender: TObject);
    procedure lvSensorsSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure tntmntmDisableClick(Sender: TObject);
    procedure tntpmn1Popup(Sender: TObject);
    procedure tntmntmUnitClick(Sender: TObject);
    procedure tntstsbr1DrawPanel(StatusBar: TStatusBar;
      Panel: TStatusPanel; const Rect: TRect);
    procedure tmrLedOffTimer(Sender: TObject);
    procedure tmrRedLedOffTimer(Sender: TObject);
    procedure tmr1Timer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FComPort:THandle;
    FSendComPort:THandle;
    FReadBuffer:TSharedRingBuf;
    FComThread:TComThread;
    FParseThread:TParseThread;
    DisableEvents:Boolean;
    procedure OpenPort;
    procedure OpenSendPort;
    procedure WMNotify(var Message: TWMNotify); message WM_NOTIFY;
    procedure ReadFromAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
    procedure WriteToAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
  public
    { Public declarations }
    procedure addData(Sensors:TList);
  end;

var
  fmMain: TfmMain;
  Debug:Boolean=false;

implementation

uses Math;

{$R *.dfm}

{ TComThread }

constructor TComThread.Create(ComPort:THandle; aBuf: TSharedRingBuf);
begin
 RingBuf  := aBuf;
 FComPort:=ComPort;
 inherited Create(false);
end;

procedure TComThread.Execute;
var
 Buffer:array[0..1023] of Byte;
 frameSize:DWORD;
 ovr:TOVERLAPPED;

 DebugBuffer:PByteArray;
 DebugPos:Word;
 writed:DWORD;
 DebugFile:THandle;
begin
 if (Debug) then Begin
  DebugBuffer:=AllocMem(10*1024);
  ZeroMemory(DebugBuffer,10*1024);
  DebugPos:=0;
  DebugFile:=INVALID_HANDLE_VALUE;
 end; 

 ZeroMemory(@ovr,Sizeof(TOVERLAPPED));
 ovr.hEvent:=CreateEvent(nil,True,False,nil);
 while not Terminated do Begin
  if (not ReadFile(FComPort,Buffer,1024,frameSize,@ovr)) and (WaitForSingleObject(ovr.hEvent,100)=WAIT_OBJECT_0) then Begin
   GetOverlappedResult(FComPort,ovr,frameSize,FALSE);
   if (frameSize>0) then Begin
    RingBuf.WriteData(Buffer,frameSize,true);

    if (Debug) then begin
     if (DebugPos+frameSize>=1024*10) then Begin
       if DebugFile=INVALID_HANDLE_VALUE then
         DebugFile:=CreateFile(PChar('buffer.dmp'), GENERIC_READ or GENERIC_WRITE,0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,0);
       if DebugFile<>INVALID_HANDLE_VALUE then
         WriteFile(DebugFile,DebugBuffer^,DebugPos,writed,nil);
       DebugPos:=0;
     end;
     CopyMemory(@DebugBuffer[DebugPos],@Buffer[0],frameSize);
     Inc(DebugPos,frameSize);
    end; 
   end;
  end;
 end;
 if Debug and (DebugPos>0) then Begin
   if DebugFile=INVALID_HANDLE_VALUE then
     DebugFile:=CreateFile(PChar('buffer.dmp'), GENERIC_READ or GENERIC_WRITE,0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,0);
   if DebugFile<>INVALID_HANDLE_VALUE then Begin
     WriteFile(DebugFile,DebugBuffer^,DebugPos,writed,nil);
     CloseHandle(DebugFile);
   end;
 end;  
 CloseHandle(ovr.hEvent);
end;

{ TParseThread }

constructor TParseThread.Create(aBuf: TSharedRingBuf);
begin
 RingBuf  := aBuf;
 LastBuffer := TSharedRingBuf.Create;
 FSensors:=TList.Create;
 inherited Create(false);
end;

destructor TParseThread.Destroy;
begin
  FSensors.Free;
  LastBuffer.Free;
  inherited;
end;

procedure TParseThread.DoPkt;
begin
 fmMain.addData(FSensors);
end;

procedure TParseThread.Execute;
var
 Buffer:array[0..127] of Byte;
 i,Readed:Integer;

 inPkt:Boolean;
 pktIndex:Byte;
 SensorData:^TSensorDataShort;

 lastPktTime, CurrTicks:DWORD;
begin
 inPkt:=False;
 pktIndex:=0;
 while not Terminated do Begin
   Readed:=RingBuf.ReadData(Buffer,128,false);
   CurrTicks:=GetTickCount();
   if (CurrTicks-lastPktTime)>300 then begin
     inPkt:=false;
     pktIndex:=0;
   end;
   for i:=0 to Readed-1 do Begin
    if (Buffer[i] and $80)<>0 then Begin
      FFreq:=(CurrTicks-lastPktTime);
      lastPktTime:=CurrTicks;
      inPkt:=true;
      pktIndex:=0;
      FSensors.Clear;
    end else
    if (Buffer[i] and $40)<>0 then Begin
      inPkt:=false;
      pktIndex:=0;
      Synchronize(DoPkt);
      FSensors.Clear;
    end else
    if (inPkt) then begin
     case (pktIndex) of
       0: begin
           New(SensorData);
           SensorData.Addr:=(Buffer[i] and $7F) shl 6;
          end;
       1: SensorData.Addr:=SensorData.Addr or (Buffer[i] and $7F);
       2: SensorData.Inst:=(Buffer[i] and $7F);
       3: SensorData.Data:=(Buffer[i] and $7F) shl 6;
       4: begin
           SensorData.Data:=SensorData.Data or (Buffer[i] and $7F);
           FSensors.Add(SensorData);
          end;
     end;
     inc(pktIndex);
     pktIndex:=pktIndex mod 5;
    end;
   end;
 end;
end;

{ TfmMain }

procedure SetTimeOuts(FHandle:THandle;Value:Word);
var
  Timeouts : COMMTIMEOUTS;
begin
  ZeroMemory(@Timeouts,sizeof(COMMTIMEOUTS));
  Timeouts.ReadIntervalTimeout := 10;
  Timeouts.ReadTotalTimeoutMultiplier := 1;
  Timeouts.ReadTotalTimeoutConstant := 100;
  Timeouts.WriteTotalTimeoutMultiplier := 0;
  Timeouts.WriteTotalTimeoutConstant := 0;

  if (not SetCommTimeouts(FHandle, Timeouts)) then exit;
end;

procedure TfmMain.OpenPort;
var
  PortDCB : TDCB;
  PortName:WideString;

begin
  if FComPort<>INVALID_HANDLE_VALUE then Begin
   if Assigned(FParseThread) then Begin
     FParseThread.Terminate;
     FParseThread.WaitFor;
     FParseThread.Free;
     FParseThread:=nil;
   end;
   if Assigned(FComThread) then Begin
    FComThread.Terminate;
    FComThread.WaitFor;
    FComThread.Free;
    FComThread:=nil;
   end;
   if Assigned(FReadBuffer) then FreeAndNil(FReadBuffer);
   CloseHandle(FComPort);
   FComPort:=INVALID_HANDLE_VALUE;
  end;

 PortName:='\\.\'+cbbFromPORT.Text;
 FComPort:=CreateFileW(PWideChar(PortName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_OVERLAPPED, 0);
 if FComPort<>INVALID_HANDLE_VALUE then Begin
   SetupComm(FComPort, 1024, 1024);

   ZeroMemory(@PortDCB,sizeof(TDCB));
   PortDCB.DCBlength := sizeof(TDCB);
   GetCommState(FComPort, PortDCB); //getting port state

   PortDCB.BaudRate := CBR_19200;
   PortDCB.ByteSize := 8;
   PortDCB.Parity := NOPARITY;
   PortDCB.StopBits := ONESTOPBIT;

   if (not SetCommState(FComPort, PortDCB)) then Exit;

   SetTimeOuts(FComPort, 2000);

   EscapeCommFunction(FComPort, 11);

   PurgeComm(FComPort, PURGE_TXCLEAR or PURGE_RXCLEAR);

   FReadBuffer:=TSharedRingBuf.Create;

   FComThread:=TComThread.Create(FComPort,FReadBuffer);
   FParseThread:=TParseThread.Create(FReadBuffer);

   jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,'Port '+PortName+' opened');

   jvprgstrystrg1.WriteString('ReadPort',cbbFromPORT.Text);
 end;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
 lvSensors.DoubleBuffered:=true;
 jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,'Loaded');

 FSendComPort:=INVALID_HANDLE_VALUE;

 cbbFromPORT.Text:=jvprgstrystrg1.ReadString('ReadPort','COM40');
 cbbEmulatePORT.Text:=jvprgstrystrg1.ReadString('WritePort','COM30');

 OpenPort;
 OpenSendPort;
end;

function getSensorValue(addr:Word;raw:Word;units:Byte):Single;
begin
  case addr of
    0://Wideband Air/Fuel
      if (units = 0) then //Lambda
      Result := (raw/3.75+68)/100
      else if(units = 1) then //Gasoline 14.7
      Result := (raw/2.55+100)/10
      else if(units = 2) then //Diesel 14.6
      Result := (raw/2.58+100)/10
      else if(units = 3) then //Methanol 6.4
      Result := (raw/5.856+43.5)/10
      else if(units = 4) then //Ethanol 9.0
      Result := (raw/4.167+61.7)/10
      else if(units = 5) then //LPG 15.5
      Result := (raw/2.417+105.6)/10
      else if(units = 6) then //CNG 17.2
      Result := (raw/2.18+117)/10;
    1: //EGT
      if(units = 0) then //Degrees Celsius
      Result := raw
      else if(units = 1) then //Degrees Fahrenheit
      Result := (raw/0.555+32);
    2: //Fluid Temp
      if(units = 0) then //Degrees Celsius Water
      Result := raw
      else if(units = 1) then //Degrees Fahrenheit Water
      Result := (raw/0.555+32)
      else if(units = 2) then //Degrees Celsius Oil
      Result := raw
      else if(units = 3) then //Degrees Fahrenheit Oil
      Result := (raw/0.555+32);
    3: //Vac
      if(units = 0) then //in/Hg (inch Mercury)
      Result := -(raw/11.39-29.93)
      else if(units = 1) then //mm/Hg (millimeters Mercury)
      Result := -(raw*2.23+760.4);
    4: //Boost
      if(units = 0) then //0-30 PSI
      Result := raw/22.73
      else if(units = 1) then //0-2 kg/cm^2
      Result := raw/329.47
      else if(units = 2) then //0-15 PSI
      Result := raw/22.73
      else if(units = 3) then //0-1 kg/cm^2
      Result := raw/329.47
      else if(units = 4) then //0-60 PSI
      Result := raw/22.73
      else if(units = 5) then //0-4 kg/cm^2
      Result := raw/329.47;
    5: //AIT
      if(units = 0) then //Celsius
      Result := raw
      else if(units = 1) then //Fahrenheit
      Result := (raw/0.555+32);
    6: //RPM
      Result := raw*19.55; //RPM
    7: //Speed
      if(units = 0) then //MPH
      Result := raw/6.39
      else if(units = 1) then //KMH
      Result := raw/3.97;
    8: //TPS
      Result := raw; //Throttle Position %
    9: //Engine Load
      Result := raw; //Engine Load %
    10: //Fluid Pressure
      if(units = 0) then //PSI Fuel
      Result := raw/5.115
      else if(units = 1) then //kg/cm^2 Fuel
      Result := raw/72.73
      else if(units = 2) then //Bar Fuel
      Result := raw/74.22
      else if(units = 3) then //PSI Oil
      Result := raw/5.115
      else if(units = 4) then //kg/cm^2 Oil
      Result := raw/72.73
      else if(units = 5) then //Bar Oil
      Result := raw/74.22;
    11: //Engine timing
      Result := raw-64; //Degree Timing
    12: //MAP
      if(units = 0) then //kPa
      Result := raw
      else if(units = 1) then //inHg
      Result := raw/3.386;
    13: //MAF
      if(units = 0) then //g/s (grams per second)
      Result := raw
      else if(units = 1) then //lb/min (pounds per minute)
      Result := raw/7.54;
    14: //Short term fuel trim
      Result := raw-100; //Fuel trim %
    15: //Long term fuel trim
      Result := raw-100; //Fuel trim %
    16: //Narrowband O2 sensor
      if(units = 0) then //Percent
      Result := raw
      else if(units = 1) then //Volts
      Result := raw/78.43;
    17: //Fuel level
      Result := raw; //Fuel Level %
    18: //Volts
      Result := raw/51.15; //Volt Meter Volts
    19: //Knock
      Result := raw/204.6; //Knock volts 0-5
    20: //Duty cycle
      if(units = 0) then //Positive Duty
      Result := raw/10.23
      else if(units = 1) then //Negative Duty
      Result := 100 - (raw/10.23);
    else Result:=-1;
  end;
end;

function getSensorName(addr:Word):string;
begin
  case addr of
    0: Result:='Wideband Air/Fuel';
    1: Result:='Exhaust Gas Temperature';
    2: Result:='Fluid Temperature';
    3: Result:='Vacuum';
    4: Result:='Boost';
    5: Result:='Air Intake Temperature';
    6: Result:='RPM';
    7: Result:='Vehicle Speed';
    8: Result:='Throttle Position';
    9: Result:='Engine Load';
    10: Result:='Fuel Pressure';
    11: Result:='Timing';
    12: Result:='MAP';
    13: Result:='MAF';
    14: Result:='Short Term Fuel Trim';
    15: Result:='Long Term Fuel Trim';
    16: Result:='Narrowband Oxygen Sensor';
    17: Result:='Fuel Level';
    18: Result:='Volt Meter';
    19: Result:='Knock';
    20: Result:='Duty Cycle';
    else Result:='Unk 0x'+IntToHex(addr,2);
  end;
end;

procedure TfmMain.addData(Sensors:TList);
var
  NewItem:TTntListItem;
  SensData:^TSensorData;
  SensorData:^TSensorDataShort;
  j,i:Integer;
  tmpString:String;
label end_add;  
begin
 //jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,Format('A: 0x%.4X, I: 0x%.2X, D: 0x%.4X',[Addr,Int,Data]));
 tmpString:=tntstsbr1.Panels[0].Text;
 tmpString[1]:='1';
 tntstsbr1.Panels[0].Text:=tmpString;
 tntstsbr1.Invalidate;
 tmrLedOff.Enabled:=true;
 DisableEvents:=true;
 lvSensors.Items.BeginUpdate;
 for j:=0 to Sensors.Count-1 do Begin
   SensorData:=Sensors.Items[j];
 for i:=0 to lvSensors.Items.Count-1 do Begin
   SensData:=lvSensors.Items.Item[i].Data;
   if ((SensData.Addr=SensorData.Addr) and (SensData.Inst=SensorData.Inst)) then begin
     SensData.Data:=SensorData.Data;
     with lvSensors.Items.Item[i].SubItems do Begin
      tmpString:=Format('0x%.4X',[SensorData.Data]);
      Strings[1]:=IntToStr(StrToInt(Strings[1])+1);
      Strings[2]:=tmpString;
      Strings[3]:=Format('%.2f',[getSensorValue(SensorData.Addr,SensorData.Data,SensData.units)]);
      goto end_add;
     end;
   end;
 end;
 New(SensData);
 NewItem:=TTntListItem.Create(lvSensors.Items);
 SensData.Addr:=SensorData.Addr;
 SensData.Inst:=SensorData.Inst;
 SensData.Data:=SensorData.Data;
 SensData.units:=jvprgstrystrg1.ReadInteger(Format('Sensor_%u_%u\Unit',[SensData.Addr,SensData.Inst]),0);
 NewItem.Data:=SensData;
 NewItem.Caption:=IntToStr(SensData.Addr);
 with NewItem.SubItems do Begin
   Add(getSensorName(SensData.Addr));
   Add('1');
   Add(Format('0x%.4X',[SensData.Data]));
   Add(Format('%.2f',[getSensorValue(SensData.Addr,SensData.Data,SensData.units)]));
 end;
 lvSensors.Items.AddItem(NewItem).Checked:=jvprgstrystrg1.ReadBoolean(Format('Sensor_%u_%u\Enabled',[SensData.Addr,SensData.Inst]),false);
end_add:
 end;
 lvSensors.AlphaSort;
 lvSensors.Items.EndUpdate;
 DisableEvents:=false;
end;

function SendData(const Buffer:Pointer;Len:WORD):Boolean;
var
 frameSize:DWORD;
 ovr:TOVERLAPPED;
Begin
 ZeroMemory(@ovr,Sizeof(TOVERLAPPED));
 ovr.hEvent:=CreateEvent(nil,True,False,nil);
 if (not WriteFile(fmMain.FSendComPort,Buffer^,Len,frameSize,@ovr)) and (WaitForSingleObject(ovr.hEvent,100)=WAIT_OBJECT_0) then Begin
  GetOverlappedResult(fmMain.FSendComPort,ovr,frameSize,FALSE);
 end;
 CloseHandle(ovr.hEvent);
 Result:=true;
end;

procedure TfmMain.OpenSendPort;
var
  PortDCB : TDCB;
  PortName:WideString;

begin
  if FSendComPort<>INVALID_HANDLE_VALUE then Begin
   tmrSend.Enabled:=false;
   CloseHandle(FSendComPort);
   FSendComPort:=INVALID_HANDLE_VALUE;
  end;

 PortName:='\\.\'+cbbEmulatePORT.Text;
 FSendComPort:=CreateFileW(PWideChar(PortName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_OVERLAPPED, 0);
 if FSendComPort<>INVALID_HANDLE_VALUE then Begin
   SetupComm(FSendComPort, 0, 1024);

   ZeroMemory(@PortDCB,sizeof(TDCB));
   PortDCB.DCBlength := sizeof(TDCB);
   GetCommState(FSendComPort, PortDCB); //getting port state

   PortDCB.BaudRate := CBR_19200;
   PortDCB.ByteSize := 8;
   PortDCB.Parity := NOPARITY;
   PortDCB.StopBits := ONESTOPBIT;

   if (not SetCommState(FSendComPort, PortDCB)) then Exit;

   SetTimeOuts(FSendComPort, 2000);

   EscapeCommFunction(FSendComPort, 11);
   PurgeComm(FSendComPort, PURGE_TXCLEAR or PURGE_RXCLEAR);

   tmrSend.Enabled:=true;

   jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,'Port '+PortName+' opened');
   jvprgstrystrg1.WriteString('WritePort',cbbEmulatePORT.Text);
 end;
end;



procedure TfmMain.tmrSendTimer(Sender: TObject);
var
 SendBuffer:array[0..1023] of Byte;
 SendLen:Word;
 i:Integer;
 SensData:^TSensorData;
 tmpString:WideString;
begin
 if (lvSensors.Items.Count<=0) then Exit;
 SendBuffer[0]:=$80;
 SendLen:=1;
 for i:=0 to lvSensors.Items.Count-1 do
   if lvSensors.Items.Item[i].Checked then Begin
    SensData:=lvSensors.Items.Item[i].Data;
    SendBuffer[SendLen]:=(SensData.Addr shr 6) and $7F;
    SendBuffer[SendLen+1]:=SensData.Addr and $7F;
    SendBuffer[SendLen+2]:=SensData.Inst;
    SendBuffer[SendLen+3]:=(SensData.Data shr 6) and $7F;
    SendBuffer[SendLen+4]:=SensData.Data and $7F;
    Inc(SendLen,5);
    if (SendLen+5>=1024) then begin
     SendData(@SendBuffer[0],SendLen);
     SendLen:=0;
    end;
   end;
 SendBuffer[SendLen]:=$40;
 SendData(@SendBuffer[0],SendLen+1);
 tmpString:=tntstsbr1.Panels[0].Text;
 tmpString[2]:='1';
 tntstsbr1.Panels[0].Text:=tmpString;
 tntstsbr1.Invalidate;
 tmrRedLedOff.Enabled:=true;
end;

procedure TfmMain.lvSensorsCompare(Sender: TObject; Item1,
  Item2: TListItem; Data: Integer; var Compare: Integer);
var
  SensData1:^TSensorData;
  SensData2:^TSensorData;
begin
  SensData1:=Item1.Data;
  SensData2:=Item2.Data;
  Compare:=CompareValue(SensData1.Addr,SensData2.Addr);
  if (Compare=0) then
    Compare:=CompareValue(SensData1.Inst,SensData2.Inst);
end;

procedure TfmMain.cbbFromPORTChange(Sender: TObject);
begin
 OpenPort;
end;

procedure TfmMain.cbbEmulatePORTChange(Sender: TObject);
begin
 OpenSendPort;
end;

procedure TfmMain.lvSensorsSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
 if Selected then lvSensors.PopupMenu:=tntpmn1 else lvSensors.PopupMenu:=nil;
end;

procedure TfmMain.tntmntmDisableClick(Sender: TObject);
begin
 lvSensors.Selected.Checked:=not lvSensors.Selected.Checked;
end;

procedure TfmMain.tntmntmUnitClick(Sender: TObject);
var
 SensData:^TSensorData;
begin
 SensData:=lvSensors.Selected.Data;
{ case SensData.Addr of
   0: begin}
       SensData.units:=TTntMenuItem(Sender).MenuIndex-2;
       lvSensors.Selected.SubItems.Strings[3]:=Format('%.2f',[getSensorValue(SensData.Addr,SensData.Data,SensData.units)]);
       TTntMenuItem(Sender).Checked:=true;
       jvprgstrystrg1.WriteInteger(Format('Sensor_%u_%u\Unit',[SensData.Addr,SensData.Inst]),SensData.units);
{   end;
 end;}
end;

procedure TfmMain.tntpmn1Popup(Sender: TObject);
var
 SensData:^TSensorData;
 i:Integer;
 MenuItem:TTntMenuItem;
 Str:WideString;
begin
 SensData:=lvSensors.Selected.Data;
 if lvSensors.Selected.Checked then tntmntmDisable.Caption:='Disable' else tntmntmDisable.Caption:='Enable';
 while tntpmn1.Items.Count>2 do Begin
  tntpmn1.Items.Delete(tntpmn1.Items.Count-1);
 end;
 case SensData.Addr of
   0: begin
      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=0);
      MenuItem.Caption:='Lambda';
      tntpmn1.Items.Add(MenuItem);

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=1);
      MenuItem.Caption:='Gasoline 14.7';
      tntpmn1.Items.Add(MenuItem);

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=2);
      MenuItem.Caption:='Diesel 14.6';
      tntpmn1.Items.Add(MenuItem);

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=3);
      MenuItem.Caption:='Methanol 6.4';
      tntpmn1.Items.Add(MenuItem); //

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=4);
      MenuItem.Caption:='Ethanol 9.0';
      tntpmn1.Items.Add(MenuItem); //

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=5);
      MenuItem.Caption:='LPG 15.5';
      tntpmn1.Items.Add(MenuItem); //

      MenuItem:=TTntMenuItem.Create(tntpmn1);
      MenuItem.OnClick:=tntmntmUnitClick;
      MenuItem.GroupIndex:=1;
      MenuItem.RadioItem:=true;
      MenuItem.AutoCheck:=true;
      MenuItem.Checked:=(SensData.units=6);
      MenuItem.Caption:='CNG 17.2';
      tntpmn1.Items.Add(MenuItem); //
      end;
   1: Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='EGT °C';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='EGT °F';
       tntpmn1.Items.Add(MenuItem); //
      end;
   2: //Fluid Temp
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='Water °C';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='Water °F';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=2);
       MenuItem.Caption:='Oil °C';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=3);
       MenuItem.Caption:='Oil °F';
       tntpmn1.Items.Add(MenuItem); //
      end;
    3: //Vac
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='in/Hg (inch Mercury)';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='mm/Hg (millimeters Mercury)';
       tntpmn1.Items.Add(MenuItem); //
      end;
    4: //Boost
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='0-30 PSI';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       Str:='0-2 kg/cm';
       MenuItem.Caption:=Str + WideChar($00B2);
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=2);
       MenuItem.Caption:='0-15 PSI';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=3);
       Str:='0-1 kg/cm';
       MenuItem.Caption:=Str + WideChar($00B2);
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=4);
       MenuItem.Caption:='0-60 PSI';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=5);
       Str:='0-4 kg/cm';
       MenuItem.Caption:=Str + WideChar($00B2);
       tntpmn1.Items.Add(MenuItem); //
      end;
    5: //AIT
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='Air °C';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='Air °F';
       tntpmn1.Items.Add(MenuItem); //
      end;
    7: //Speed
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='MPH';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='km/h';
       tntpmn1.Items.Add(MenuItem); //
      end;
    10: //Fluid Pressure
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='Fuel PSI';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       Str:='Fuel kg/cm';
       MenuItem.Caption:=Str + WideChar($00B2);
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=2);
       MenuItem.Caption:='Fuel Bar';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=3);
       MenuItem.Caption:='Oil PSI';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=4);
       Str:='Oil kg/cm';
       MenuItem.Caption:=Str + WideChar($00B2);
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=5);
       MenuItem.Caption:='Oil Bar';
       tntpmn1.Items.Add(MenuItem); //
      end;
    12: //MAP
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='kPa';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='inHg';
       tntpmn1.Items.Add(MenuItem); //
      end;
    13: //MAF
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='g/s';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='lb/min';
       tntpmn1.Items.Add(MenuItem); //
      end;
    16: //Narrowband O2 sensor
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='Percent';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='Volts';
       tntpmn1.Items.Add(MenuItem); //
      end;
    20: //Duty cycle
      Begin
       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=0);
       MenuItem.Caption:='Positive Duty';
       tntpmn1.Items.Add(MenuItem); //

       MenuItem:=TTntMenuItem.Create(tntpmn1);
       MenuItem.OnClick:=tntmntmUnitClick;
       MenuItem.GroupIndex:=1;
       MenuItem.RadioItem:=true;
       MenuItem.AutoCheck:=true;
       MenuItem.Checked:=(SensData.units=1);
       MenuItem.Caption:='Negative Duty';
       tntpmn1.Items.Add(MenuItem); //
      end;
 end;
end;

procedure TfmMain.tntstsbr1DrawPanel(StatusBar: TStatusBar;
  Panel: TStatusPanel; const Rect: TRect);
var
  top:Integer;
begin
 if Panel.Index<>0 then Exit;
 with StatusBar.Canvas do begin
   Brush.Style:=bsSolid;
   if Panel.Text[1]='1' then
    Brush.Color:=clGreen
   else
    Brush.Color:=clBtnFace;
   FillRect(Classes.Rect(2,Rect.Top,2+(Rect.Bottom-Rect.Top),Rect.Top+(Rect.Bottom-Rect.Top)));

   if Panel.Text[2]='1' then
    Brush.Color:=clRed
   else
    Brush.Color:=clBtnFace;
  FillRect(Classes.Rect(2+(Rect.Bottom-Rect.Top)+5,Rect.Top,2+(Rect.Bottom-Rect.Top)+5+(Rect.Bottom-Rect.Top),Rect.Top+(Rect.Bottom-Rect.Top)));
 end;

end;

procedure TfmMain.tmrLedOffTimer(Sender: TObject);
var
 tmpString:WideString;
begin
 tmrLedOff.Enabled:=false;
 tmpString:=tntstsbr1.Panels[0].Text;
 tmpString[1]:='0';
 tntstsbr1.Panels[0].Text:=tmpString;
 tntstsbr1.Invalidate;
end;

procedure TfmMain.tmrRedLedOffTimer(Sender: TObject);
var
 tmpString:WideString;
begin
 tmrRedLedOff.Enabled:=false;
 tmpString:=tntstsbr1.Panels[0].Text;
 tmpString[2]:='0';
 tntstsbr1.Panels[0].Text:=tmpString;
 tntstsbr1.Invalidate;
end;

procedure TfmMain.tmr1Timer(Sender: TObject);
begin
 if Assigned(FParseThread) then tntstsbr1.Panels[1].Text:=Format('%u ms',[FParseThread.FFreq]);
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
 FParseThread.Terminate;
 FParseThread.WaitFor;
 FParseThread.Free;
 FParseThread:=nil;
 FComThread.Terminate;
 FComThread.WaitFor;
 FComThread.Free;
 jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,'Closed');
 jvlgfl1.SaveToFile(jvlgfl1.FileName);
end;

procedure TfmMain.WMNotify(var Message: TWMNotify);
var
 OldChecked, NewChecked: Boolean;
 SensData:^TSensorData;
begin
 if not DisableEvents then
 with Message do
   if NMHdr.hwndFrom =  lvSensors.Handle then
     if NMHdr.code = LVN_ITEMCHANGED then
     begin
       OldChecked := Boolean(PNMListView(NMHdr).uOldState and (1 shl 13) <> 0);
       NewChecked := Boolean(PNMListView(NMHdr).uNewState and (1 shl 13) <> 0);
       if OldChecked <> NewChecked then Begin
        jvlgfl1.Add(FormatDateTime('tt.zzz',Now),lesInformation,'Checked '+IntToStr(SensData.Addr));
        SensData:=lvSensors.Items[PNMListView(NMHdr).iItem].Data;
        jvprgstrystrg1.WriteBoolean(Format('Sensor_%u_%u\Enabled',[SensData.Addr,SensData.Inst]),NewChecked);
       end;
         //Caption := Format("?????? ????????: %d, ?????????: %s", [PNMListView(NMHdr).iItem, States[NewChecked]])
     end;
 inherited;
end;

procedure TfmMain.ReadFromAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
var
  i:Integer;
begin
 for i:=0 to lvSensors.Columns.Count-1 do Begin
   lvSensors.Columns.Items[i].Width:=AppStorage.ReadInteger(AppStorage.ConcatPaths([BasePath, 'columns\'+lvSensors.Columns.Items[i].Caption+'\width']), lvSensors.Columns.Items[i].Width);
   lvSensors.Columns.Items[i].Index:=AppStorage.ReadInteger(AppStorage.ConcatPaths([BasePath, 'columns\'+lvSensors.Columns.Items[i].Caption+'\index']), lvSensors.Columns.Items[i].Index);
 end;
end;

procedure TfmMain.WriteToAppStorage(AppStorage: TJvCustomAppStorage; const BasePath: string);
var
  i:Integer;
begin
 for i:=0 to lvSensors.Columns.Count-1 do Begin
   AppStorage.WriteInteger(AppStorage.ConcatPaths([BasePath, 'columns\'+lvSensors.Columns.Items[i].Caption+'\width']), lvSensors.Columns.Items[i].Width);
   AppStorage.WriteInteger(AppStorage.ConcatPaths([BasePath, 'columns\'+lvSensors.Columns.Items[i].Caption+'\index']), lvSensors.Columns.Items[i].Index);
 end;
end;

end.
