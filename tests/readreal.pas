{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program rr;
var x, y: real; i: integer;
begin
  write('x? '); readln(x);
  write('y? '); readln(y);
  writeln(x + y:0:3);
  write('i x? '); read(i, x); readln;
  writeln(i, ' ', x:0:2)
end.
