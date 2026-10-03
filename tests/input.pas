{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program inputtest;
{ read / readln: numbers, several values on a line, strings, characters, bytes, array elements }
var n, m: integer; c: char; s: string[20]; b: byte; a: array[1..3] of integer;
begin
  write('number? ');
  readln(n);
  writeln('n=', n);
  write('two? ');
  readln(n, m);
  writeln(n + m);
  write('name? ');
  readln(s);
  writeln('hello ', s, '!');
  readln(c);
  writeln('char=', c);
  readln(b);
  writeln(b);
  readln(a[1], a[2], a[3]);
  writeln(a[1] + a[2] * a[3])
end.
