{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program valtest;
{ Val: string to integer; code is 0 if ok, else the position of the first bad character }
uses Crt;
var n, code: integer;
begin
  val('12345', n, code); writeln(n, ' ', code);   { 12345 0 }
  val('-42', n, code);   writeln(n, ' ', code);   { -42 0 }
  val('  7', n, code);   writeln(n, ' ', code);   { 7 0 }
  val('12x4', n, code);  writeln(n, ' ', code);   { 0 3 }
  val('', n, code);      writeln(n, ' ', code);   { 0 1 }
  val('99', n, code);    writeln(n + 1, ' ', code)  { 100 0 }
end.
