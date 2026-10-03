program test;
const max = 10;
var i, f, s: integer;
    ok: boolean;
    c: char;
begin
  writeln('Hello from C64 Pascal');
  s := 0;
  for i := 1 to max do s := s + i;
  writeln('sum 1..10 = ', s);
  f := 1;
  i := 1;
  while i <= 7 do begin f := f * i; i := i + 1 end;
  writeln('7! = ', f);
  i := 0;
  repeat i := i + 3 until i > 10;
  writeln('i = ', i);
  if (f div 7 = 720) and (f mod 7 = 0) then writeln('div mod ok') else writeln('div mod BAD');
  writeln('neg ', -f div 8);
  ok := not (s > 50);
  writeln(ok, ' ', 1 < 2);
  c := 'A';
  write(c); write('b'); writeln;
  for i := 5 downto 1 do write(i, ' ');
  writeln
end.
