{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program directives;
{ conditional compilation: the same source on C64, C128 and Plus/4 }
{$DEFINE DEBUG}
{$DEFINE TWICE}
{$UNDEF TWICE}
var n: integer;
begin
{$IFDEF C64}
  writeln('machine: C64');
{$ENDIF}
{$IFDEF C128}
  writeln('machine: C128');
{$ENDIF}
{$IFDEF PLUS4}
  writeln('machine: PLUS4');
{$ENDIF}
{$IFDEF DEBUG}
  writeln('debug on');
{$ELSE}
  writeln('debug OFF');
{$ENDIF}
{$IFNDEF TWICE}
  writeln('twice undefined');
{$ENDIF}
{$IFDEF NOTHING}
  this is not Pascal at all ! @ # $ %
  {$IFDEF DEBUG}
    nested text, still skipped
  {$ELSE}
    also skipped
  {$ENDIF}
{$ELSE}
  writeln('else branch');
{$ENDIF}
{$R+}
  n := 0;
{$IFDEF VIC}  n := n + 1; {$ENDIF}
{$IFDEF SID}  n := n + 10; {$ENDIF}
{$IFDEF TED}  n := n + 100; {$ENDIF}
  writeln(n)
end.
