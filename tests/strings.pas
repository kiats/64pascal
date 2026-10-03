{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program strings;
{ strings: concatenation, indexing, comparison, built-in routines, parameters }
type
  name = string[20];
var
  s, t: string;
  n: name;
  c: char;
  i: integer;
  words: array[1..3] of string[10];

procedure show(s: string);
begin
  writeln('[', s, ']')
end;

procedure shout(var s: string);
var i: integer;
begin
  for i := 1 to length(s) do s[i] := upcase(s[i])
end;

begin
  s := 'Hello';
  t := s + ', ' + 'World';
  writeln(t);                                   { Hello, World }
  writeln(length(t));                           { 12 }
  writeln(copy(t, 8, 5));                       { World }
  writeln(pos('World', t), ' ', pos('xyz', t)); { 8 0 }
  c := t[1];
  writeln(c, ' ', t[5]);                        { H o }
  t[1] := 'J';
  writeln(t);                                   { Jello, World }
  n := 'Pascal';
  writeln(n, ' ', length(n));                   { Pascal 6 }
  delete(t, 6, 7);
  writeln(t);                                   { Jello }
  insert('Hel', t, 1);
  writeln(t);                                   { HelJello }
  str(12345, s);
  writeln(s, '!', length(s));                   { 12345!5 }
  str(-7, s);
  writeln(s);                                   { -7 }
  if s = '-7' then writeln('equal') else writeln('different');
  if 'abc' < 'abd' then writeln('less');
  if n > 'Pascal' then writeln('wrong') else writeln('not greater');
  words[1] := 'one';
  words[2] := 'two';
  words[3] := words[1] + words[2];
  for i := 1 to 3 do writeln(i, ': ', words[i]);
  show(n + '!');                                { [Pascal!] }
  s := 'shout me';
  shout(s);
  writeln(s);                                   { SHOUT ME }
  s := 'a';
  s := s + 'b' + c;
  writeln(s);                                   { abH }
  writeln(chr(ord('A') + 2));                   { C }
  s := '';
  for i := 1 to 5 do s := s + chr(64 + i);
  writeln(s)                                    { ABCDE }
end.
