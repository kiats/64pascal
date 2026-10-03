{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program real1;
var x, y: real; i: integer;
begin
  x := 1.5;
  y := 2.25;
  writeln(x + y);
  writeln(x * y:10:4);
  writeln(y / x:0:3);
  i := 7;
  writeln(i / 2:0:2);
  writeln(x - y:8:3);
  if x < y then writeln('lt');
  if x = 1.5 then writeln('eq');
  writeln(trunc(y), ' ', round(x), ' ', round(-2.5));
  writeln(sqrt(2.0):0:6);
  writeln(100.0 / 3.0)
end.
