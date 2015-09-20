{
  Ring buffer and two concurrent threads.
  (c) Kid_Deceiver
}
unit ringbuffer;

interface

uses SyncObjs;

const
  RINGBUF_SIZE = 4096;

type
  TBytes = array[0..MaxInt - 1] of Byte;
{
  Ring buffer for 2 parallel threads: "reader" and "writer"
}
  TSharedRingBuf = class
    private
      Rptr      : Integer;  // points to byte next read starts at
      Wptr      : Integer;  // points to byte next write starts at
      Buf       : array[0..RINGBUF_SIZE-1] of Byte; // ring buffer
      LockRead  : TCriticalSection;     // synch access to Rptr
      LockWrite : TCriticalSection;     // synch access to Wptr
      LockDebug : TCriticalSection;     // sync access to stdout
      procedure InternalRead( var Buffer; Count : Integer );
      procedure InternalWrite( var Buffer; Count : Integer );
      function  RoomToWrite(): Integer; // how many bytes can be written
    public
      constructor Create();
      destructor  Destroy(); override;
      function  RoomToRead() : Integer; // how many bytes can be read
      procedure Reset;                  // initialize internal buffer state
      function  ReadData( var Buffer;  Count : Integer; Block : Boolean ) : Integer;
      function  WriteData( var Buffer; Count : Integer; Block : Boolean ) : Integer;
  end;

implementation

uses SysUtils;

{
  --------- Public functions of TSharedRingBuf -----------
}
constructor TSharedRingBuf.Create;
begin
  LockRead  := TCriticalSection.Create(); // to protect Rptr;
  LockWrite := TCriticalSection.Create(); // to protect Wptr;
  LockDebug := TCriticalSection.Create(); // to protect stdout
  Reset();
end;

destructor TSharedRingBuf.Destroy;
begin
  LockDebug.Free;
  LockWrite.Free;
  LockRead.Free;
end;

{
  Retrieve data from the ring buffer. Called from context of "reader" thread.

    Buffer - buffer to fill in with retrieved bytes
    Count  - size of Buffer in bytes
    Block  - if False, the function will try to retrieve bytes,
             which are are already in the buffer (and are not read yet)
             if True - it will wait until get all Count bytes
             (note: timeout is notchecked! endless loop possible!)

  Returns number of bytes read actually.
}
function TSharedRingBuf.ReadData(var Buffer; Count: Integer; Block: Boolean): Integer;
var
  RoomRead : Integer;  // read space we currently have
  NtoRead  : Integer;  // data length for single read attempt
begin
  Result := 0;
  repeat
    if (Result > 0) then Sleep( Random(50) );        // let's writer writes
    RoomRead := RoomToRead();                        // locks Wptr inside
    NtoRead  := Count;                               // desired bytes to read
    if NtoRead > RoomRead then NtoRead := RoomRead;  // actual number
    InternalRead( TBytes(Buffer)[Result], NtoRead ); // get from buffer (locks Rptr)
    Dec( Count, NtoRead );                           // remainder
    Inc( Result, NtoRead );                          // done
  until (Count = 0) or (not Block);
end;

{
  Write data to the ring buffer. Called from context of "writer" thread.
  Returns number of bytes written actually
}
function TSharedRingBuf.WriteData(var Buffer; Count: Integer; Block: Boolean): Integer;
var
  RoomWrite : Integer;  // write space we currently have
  NtoWrite  : integer;  // data length for single write attempt
begin
  Result := 0;
  repeat
    if (Result > 0) then Sleep( Random(50) );           // let's reader reads
    RoomWrite := RoomToWrite();                         // locks Rptr inside
    NtoWrite  := Count;                                 // desired bytes to write
    if NtoWrite > RoomWrite then NtoWrite := RoomWrite; // actual number
    InternalWrite( TBytes(Buffer)[Result], NtoWrite );  // send to buffer (locks Wptr)
    Dec( Count, NtoWrite);                              // remainder
    Inc( Result, NtoWrite );                            // written
  until (Count = 0) or (not Block);
end;
 
{
  --------- Private functions of TSharedRingBuf -----------
}
procedure TSharedRingBuf.Reset;
begin
  Rptr := 0;  // it means nothing can be read,
  Wptr := 0;  // and up to RINGBUF_SIZE bytes can be written
end;
 
{
  How many bytes can be read from the buffer?
  Note: This procedure can be called from "reader" thread only
}
function TSharedRingBuf.RoomToRead: Integer;
begin
  LockWrite.Enter;                  // forbide Wptr change by write thread
  Result := Wptr - Rptr;
  if (Rptr > Wptr) then Inc( Result, RINGBUF_SIZE );
  LockWrite.Leave;
end;
 
{
  How many bytes can be written to the buffer?
  Note: This procedure can be called from "write" thread only
}
function TSharedRingBuf.RoomToWrite: Integer;
begin
  LockRead.Enter;                   // forbide Rptr change by reade thread
  Result := Rptr - Wptr;
  if (Rptr <= Wptr) then Inc( Result, RINGBUF_SIZE );
  LockRead.Leave;
  if Result > 0 then Dec( Result ); // trick: "Wptr never catches up Rptr"
end;
 
{
  Direct extraction bytes from the ring buffer.
  Caller must check Count value with RoomToRead before.
}
procedure TSharedRingBuf.InternalRead(var Buffer; Count: Integer);
var
  i : Integer;
begin
  // plain data transfer, no room check
  for i := 0 to Count-1 do
    TBytes(Buffer)[i] := Buf[ (Rptr + i) mod RINGBUF_SIZE ];
  // "read" thread changes shared Rptr
  LockRead.Enter;
  Rptr := (Rptr + Count) mod RINGBUF_SIZE;
  LockRead.Leave;
end;
 
{
  Direct addition bytes to the ring buffer.
  Caller must check Count value with RoomToWrite before.
}
procedure TSharedRingBuf.InternalWrite(var Buffer; Count: Integer);
var
  i : Integer;
begin
  // plain data transfer, no room check
  for i := 0 to Count-1 do
    Buf[ (Wptr + i) mod RINGBUF_SIZE ] := TBytes(Buffer)[i];
  // "write" thread changes shared Wptr
  LockWrite.Enter;
  Wptr := (Wptr + Count) mod RINGBUF_SIZE;
  LockWrite.Leave;
end;
 
end.

