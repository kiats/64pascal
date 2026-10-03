{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program ptr2;
type
  PReal = ^real;
  PItem = ^Item;
  Item = record
    x: real;
    name: string[6];
    next: PItem
  end;
var
  pr: PReal;
  a, b: PItem;
  r: real;
  n: integer;
begin
  new(pr);
  pr^ := 2.5;
  pr^ := pr^ * 3;
  writeln(pr^:0:2);
  r := 1.25;
  pr := @r;
  pr^ := pr^ + 1;
  writeln(r:0:2);
  new(a);
  a^.x := 0.5;
  a^.name := 'first';
  a^.next := nil;
  new(b);
  b^.x := a^.x * 4;
  b^.name := 'second';
  b^.next := a;
  writeln(b^.name, ' ', b^.x:0:1, ' ', b^.next^.name, ' ', b^.next^.x:0:2);
  n := 0;
  a := b;
  while a <> nil do
  begin
    n := n + 1;
    a := a^.next
  end;
  writeln(n);
  dispose(b)
end.
