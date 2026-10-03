{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program absol;
{ absolute variables: a byte at a fixed address, here the VIC border colour }
const screen = $0400;
var border: byte absolute $D020;
    first: byte absolute screen;
    b: byte;
    i: integer;
begin
  border := 2;
  b := 200;
  b := b + 100;
  writeln('b = ', b);
  writeln('border = ', border);
  first := 1;
  writeln('first = ', first);
  for b := 250 to 255 do write(b, ' ');
  writeln;
  i := 300;
  b := i;
  writeln('300 as byte = ', b)
end.
