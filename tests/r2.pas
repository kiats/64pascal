{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program r2;
{ record types declared inline in var sections, records inside records }
type
  date = record day, month: byte; year: integer end;
var
  r, s: record a: integer; b: string[5]; c: char end;
  d: record when: date; note: string[8] end;
  n: integer;
begin
  r.a := 42;
  r.b := 'abc';
  r.c := 'z';
  s := r;
  s.b := s.b + 'de';
  writeln(r.a, ' ', r.b, ' ', r.c, ' ', s.b);          { 42 abc z abcde }
  d.when.day := 24;
  d.when.month := 12;
  d.when.year := 1982;
  d.note := 'c64';
  n := d.when.year - 1900 + d.when.day;
  writeln(n, ' ', d.note, ' ', d.when.month)           { 106 c64 12 }
end.
