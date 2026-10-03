{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program real4;
var x, r: real; s: string[20]; i, code, n: integer;
begin
  Str(3.14159:0:2, s); writeln('[', s, ']');
  Str(-2.5:8:1, s); writeln('[', s, ']');
  Str(1234.5, s); writeln('[', s, ']');
  Val('2.75', x, code); writeln(x:0:3, ' ', code);
  Val('1e3', x, code); writeln(x:0:1, ' ', code);
  Val('12x', x, code); writeln(x:0:1, ' ', code);
  Val('42', i, code); writeln(i, ' ', code);
  writeln(random(1), ' ', random(10) < 10);
  r := random; writeln((r >= 0) and (r < 1));
  n := 0;
  for i := 1 to 100 do begin r := random; if r < 0.5 then n := n + 1 end;
  writeln(n > 25, ' ', n < 75);
  randomize; writeln(random(100) < 100);
  x := 0;
  for i := 1 to 1000 do x := x + random(6);
  writeln(x / 1000:0:1)
end.
