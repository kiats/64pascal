{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program records;
{ records: fields, nesting, arrays of records, whole-record assignment, parameters }
type
  point = record x, y: integer end;
  person = record
    name: string[12];
    age: byte;
    pos: point;
    scores: array[1..3] of integer;
  end;
var
  p, q: point;
  who: person;
  crowd: array[1..3] of person;
  i, total: integer;

procedure move(var pt: point; dx, dy: integer);
begin
  pt.x := pt.x + dx;
  pt.y := pt.y + dy
end;

function dist2(a, b: point): integer;
begin
  dist2 := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
end;

procedure birthday(var w: person);
begin
  w.age := w.age + 1
end;

begin
  p.x := 3;
  p.y := 4;
  q := p;
  q.x := 10;
  writeln(p.x, ',', p.y, ' ', q.x, ',', q.y);          { 3,4 10,4 }
  move(p, 1, 1);
  writeln(p.x, ',', p.y);                              { 4,5 }
  writeln(dist2(p, q));                                { 37 }
  who.name := 'Ada';
  who.age := 36;
  who.pos := p;
  who.scores[2] := 99;
  birthday(who);
  writeln(who.name, ' ', who.age, ' ', who.pos.x, ' ', who.scores[2]);   { Ada 37 4 99 }
  for i := 1 to 3 do
  begin
    crowd[i].name := 'P' + chr(48 + i);
    crowd[i].age := 20 + i;
    crowd[i].pos.x := i * 10
  end;
  total := 0;
  for i := 1 to 3 do total := total + crowd[i].age + crowd[i].pos.x;
  writeln(total);                                      { 126 }
  writeln(crowd[2].name, ' ', length(crowd[3].name));  { P2 2 }
  crowd[1] := who;
  writeln(crowd[1].name, crowd[1].age)                 { Ada37 }
end.
