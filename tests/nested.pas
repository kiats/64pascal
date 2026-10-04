{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program nested;
{ nested procedures and functions: access to the variables and parameters of the routines around, static links }
type
  arr = array[1..3] of integer;
var
  g, t: integer;
  av: arr;

{ three levels, recursion in the innermost routine, a call between siblings }
procedure a;
  procedure b;
    procedure c(n: integer);
    begin
      g := g + n;
      writeln('c ', n);
      if n > 0 then c(n - 1)
    end;
  begin
    c(2);
    writeln('b done')
  end;
  procedure d;
  begin
    b
  end;
begin
  b;
  d
end;

{ arrays, a var parameter and a string parameter of the routine around }
procedure outer(var v: arr; s: string);
  var loc: arr;
  procedure fill;
  begin
    loc[1] := 10;
    loc[2] := 20;
    loc[3] := 30;
    v[2] := 99
  end;
  procedure show;
  begin
    writeln(loc[1], ' ', loc[2], ' ', loc[3], ' ', v[2], ' ', s)
  end;
begin
  fill;
  show
end;

{ integers, a char, a boolean, value and var parameters; the outer routine calls itself: every activation has its own frame }
procedure counter(n: integer; var total: integer; flag: boolean);
var local: integer;
    c: char;
    b: boolean;
  procedure add(k: integer);
  begin
    local := local + k + n;
    total := total + k;
    c := 'x';
    b := flag
  end;
  function twice(k: integer): integer;
  begin
    twice := local * 2 + k
  end;
begin
  local := 100;
  total := 0;
  c := 'a';
  b := false;
  add(1);
  add(2);
  writeln(local, ' ', total, ' ', c, ' ', b, ' ', twice(5));
  if n > 0 then counter(n - 1, total, not flag)
end;

{ the variables of the grandparent and of the parent }
procedure p;
  var x: integer;
  procedure q(y: integer);
    var z: integer;
    procedure r;
    begin
      x := x + 1;
      z := z + y;
      writeln(x, ' ', y, ' ', z)
    end;
  begin
    z := 10;
    r;
    r
  end;
begin
  x := 0;
  q(5);
  writeln('x=', x)
end;

begin
  g := 0;
  a;
  writeln(g);
  av[1] := 1;
  av[2] := 2;
  av[3] := 3;
  outer(av, 'hello');
  writeln(av[2]);
  t := 0;
  counter(1, t, true);
  writeln('t=', t);
  p
end.
