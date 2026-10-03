{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program ptrtest;
type
  PNode = ^Node;
  Node = record
    value: integer;
    next: PNode
  end;
  PInt = ^integer;
var
  head, p, q: PNode;
  ipt: PInt;
  n, i, sum: integer;
begin
  new(ipt);
  ipt^ := 42;
  writeln('ipt^ = ', ipt^);
  n := 7;
  ipt := @n;
  ipt^ := ipt^ + 1;
  writeln('n = ', n);
  head := nil;
  for i := 1 to 5 do
  begin
    new(p);
    p^.value := i * i;
    p^.next := head;
    head := p
  end;
  sum := 0;
  q := head;
  while q <> nil do
  begin
    write(q^.value, ' ');
    sum := sum + q^.value;
    q := q^.next
  end;
  writeln;
  writeln('sum = ', sum);
  while head <> nil do
  begin
    p := head;
    head := head^.next;
    dispose(p)
  end;
  new(p);
  p^.value := 99;
  writeln(p^.value);
  if head = nil then writeln('empty')
end.
