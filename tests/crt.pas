{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program crttest;
{ Crt unit: cursor, colours, #nn characters, ClrEol, KeyPressed, ReadKey }
uses Crt;
var c: char;
begin
  ClrScr;
  TextBackground(1);
  TextColor(14);
  GotoXY(5, 3);
  write('Crt unit ', #65, #66, #67);
  GotoXY(1, 5);
  TextColor(10);
  write('x=', WhereX, ' y=', WhereY);       { x=4 y=5 }
  GotoXY(10, 7);
  write('1234567890');
  GotoXY(13, 7);
  ClrEol;                                    { leaves 123 }
  GotoXY(1, 9);
  TextColor(15);
  write(KeyPressed);                         { FALSE }
  Delay(200);
  GotoXY(1, 11);
  write('press a key: ');
  c := ReadKey;
  writeln(c, ' ', ord(c))
end.
