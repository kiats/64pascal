{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program r1;
type point = record x, y: integer end;
var p, q: point;
begin
  p.x := 3;
  p.y := 4;
  q := p;
  q.x := 10;
  writeln(p.x, ',', p.y, ' ', q.x, ',', q.y)
end.
