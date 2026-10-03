{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program procs;
{ procedures, functions, recursion, var parameters, locals }
var g: integer;

procedure hello;
begin
  writeln('hello from procedure')
end;

function fact(n: integer): integer;
begin
  if n <= 1 then fact := 1 else fact := n * fact(n - 1)
end;

function fib(n: integer): integer;
begin
  if n < 2 then fib := n else fib := fib(n - 1) + fib(n - 2)
end;

procedure swap(var a, b: integer);
var t: integer;
begin
  t := a; a := b; b := t
end;

procedure count(n: integer);
var i: integer;
begin
  for i := 1 to n do write(i, ' ');
  writeln
end;

{ recursion inside a for loop: the loop limit must survive the recursive calls }
procedure tri(n: integer);
var i: integer;
begin
  if n > 0 then
    for i := 1 to 2 do begin write(n); tri(n - 1) end
end;

function max(a, b: integer): integer;
begin
  if a > b then max := a else max := b
end;

var x, y: integer;
begin
  hello;
  writeln('fact(7) = ', fact(7));
  writeln('fib(15) = ', fib(15));
  x := 1; y := 2;
  swap(x, y);
  writeln(x, ' ', y);
  count(5);
  tri(3); writeln;
  writeln(fact(4) + fib(10) * 2);
  writeln(max(3, max(9, 4)));
  g := 5;
  swap(g, x);
  writeln(g, ' ', x)
end.
