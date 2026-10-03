{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program a1;
var a: array[1..5] of integer;
    b: array[1..5] of integer;
    i: integer;
begin
  for i := 1 to 5 do a[i] := i * i;
  writeln(a[3]);
  b := a;
  writeln(b[3]);
  b[3] := 100;
  writeln(a[3], ' ', b[3])
end.
