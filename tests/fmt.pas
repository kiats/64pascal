{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program fmt;
var i: integer; s: string[10]; c: char; b: boolean; x: real;
begin
  i := 42;
  writeln('[', i:6, '][', -i:6, '][', i:1, ']');
  s := 'abc';
  writeln('[', s:8, ']');
  c := 'z'; writeln('[', c:3, ']');
  b := true; writeln('[', b:6, '][', false:7, ']');
  x := 2.5;
  writeln('[', x:8:2, ']', i:4, x:7:1);
  writeln(i:3, i*2:5, i*3:5)
end.
