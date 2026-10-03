{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program arrays;
{ arrays: 1-D, 2-D, other index types, whole assignment, parameters, sieve }
type
  vec  = array[1..5] of integer;
  grid = array[0..2, 0..3] of integer;
var
  a: vec;
  b: array[1..5] of integer;
  g: grid;
  c: array['a'..'e'] of byte;
  t: array[-2..2] of boolean;
  p: array[2..50] of boolean;
  i, j, sum: integer;

procedure fill(var v: vec; n: integer);
var k: integer;
begin
  for k := 1 to 5 do v[k] := k * n
end;

function total(v: vec): integer;
var k, s: integer;
begin
  s := 0;
  for k := 1 to 5 do s := s + v[k];
  total := s
end;

begin
  for i := 1 to 5 do a[i] := i * i;
  sum := 0;
  for i := 1 to 5 do sum := sum + a[i];
  writeln('sum of squares = ', sum);            { 55 }
  b := a;
  b[3] := 100;
  writeln(a[3], ' ', b[3]);                      { 9 100 }
  for i := 0 to 2 do
    for j := 0 to 3 do
      g[i, j] := i * 10 + j;
  writeln(g[2, 3], ' ', g[1][2], ' ', g[0, 0]);  { 23 12 0 }
  fill(a, 3);
  writeln(a[1], ' ', a[5]);                      { 3 15 }
  writeln(total(a));                             { 45 }
  c['c'] := 7;
  c['a'] := 200;
  writeln(c['c'] + c['a']);                      { 207 }
  t[-2] := true;
  t[0] := false;
  writeln(t[-2], ' ', t[0]);                     { TRUE FALSE }
  for i := 2 to 50 do p[i] := true;              { sieve of Eratosthenes }
  for i := 2 to 7 do
    if p[i] then
      for j := 2 to 50 div i do p[i * j] := false;
  for i := 2 to 50 do
    if p[i] then write(i, ' ');
  writeln
end.
