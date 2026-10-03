{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program ctl1;
{ Break, Continue, Exit, Halt, Inc, Dec, Odd, Succ, Pred, shl, shr, forward declarations, string constants }
const
  greeting = 'hello';
  bye = 'bye!';
type
  arr = array[1..5] of integer;
var
  i, j, n: integer;
  b: byte;
  c: char;
  a: arr;

procedure ping(n: integer); forward;
function isEven(n: integer): boolean; forward;

procedure pong(n: integer);
begin
  if n > 0 then
  begin
    write('pong', n, ' ');
    ping(n - 1)
  end
end;

procedure ping(n: integer);
begin
  if n > 0 then
  begin
    write('ping', n, ' ');
    pong(n - 1)
  end
end;

function isEven(n: integer): boolean;
begin
  isEven := not odd(n)
end;

procedure firstNeg(var x: arr);
var k: integer;
begin
  for k := 1 to 5 do
    if x[k] < 0 then
    begin
      writeln('neg at ', k);
      exit
    end;
  writeln('no negative')
end;

function find(v: integer): integer;
var k: integer;
begin
  find := 0;
  for k := 1 to 5 do
    case a[k] of
      0..99: if a[k] = v then
             begin
               find := k;
               exit
             end;
    end
end;

begin
  writeln(greeting, ' ', bye);
  i := 0;
  while true do
  begin
    inc(i);
    if i = 3 then continue;
    if i > 6 then break;
    write(i, ' ')
  end;
  writeln;
  i := 0;
  repeat
    i := i + 1;
    if odd(i) then continue;
    write(i, ' ');
    if i >= 8 then break
  until i > 100;
  writeln;
  for i := 1 to 3 do
    for j := 1 to 3 do
    begin
      if j = 2 then continue;
      if (i = 2) and (j = 3) then break;
      write(i, j, ' ')
    end;
  writeln;
  for i := 1 to 10 do
    case i of
      1..3: write('a');
      4: write('b');
      5: break;
      else write('x')
    end;
  writeln;
  for i := 1 to 3 do
  begin
    for j := 1 to 5 do
    begin
      case j of 2: continue; 4: break end;
      write(j)
    end;
    write('|')
  end;
  writeln;
  n := 10;
  inc(n);
  inc(n, 5);
  dec(n);
  dec(n, 2);
  writeln(n);
  b := 250;
  inc(b, 3);
  writeln(b);
  a[3] := 7;
  inc(a[3]);
  inc(a[3], 10);
  dec(a[3]);
  writeln(a[3]);
  c := 'a';
  inc(c);
  writeln(c);
  writeln(succ(5), ' ', pred(5), ' ', succ('a'), ' ', pred('z'));
  writeln(odd(3), ' ', odd(4));
  writeln(1 shl 4, ' ', 256 shr 3, ' ', 3 shl 1 + 1);
  a[1] := 5; a[2] := -1; a[3] := 9; a[4] := 20; a[5] := 3;
  firstNeg(a);
  writeln(find(20));
  writeln(find(77));
  ping(3);
  writeln;
  writeln(isEven(4), isEven(7));
  writeln('before halt');
  halt;
  writeln('not shown')
end.
