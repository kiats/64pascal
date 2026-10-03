{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program textgame;
{ THE LOST TREASURE - a small text adventure for 64Pascal.
  Find the key and the lamp, open the iron door in the cave
  and take the gold.  Commands: n e s w, go <dir>, look, take
  <thing>, get <thing>, drop <thing>, inv, help, quit. }
uses Crt;

const
  nitems = 4;
  carried = 0;

type
  sstr = string[20];

var
  desc: array[1..8] of string[60];
  rname: array[1..8] of string[14];
  ex: array[1..8, 1..4] of integer;     { exits: north east south west }
  iname: array[1..4] of sstr;
  iloc: array[1..4] of integer;         { room of an item, 0 = carried }
  room, moves, d, i: integer;
  cmd: string[30];
  verb, noun: sstr;
  done: boolean;

procedure SetEx(r, n, e, s, w: integer);
begin
  ex[r, 1] := n;
  ex[r, 2] := e;
  ex[r, 3] := s;
  ex[r, 4] := w
end;

procedure Init;
begin
  rname[1] := 'Cottage';
  desc[1] := 'A tiny cottage. Sunlight falls through a dusty window.';
  SetEx(1, 0, 2, 0, 0);
  rname[2] := 'Garden';
  desc[2] := 'An overgrown garden. The gate to the east is open.';
  SetEx(2, 0, 3, 0, 1);
  rname[3] := 'Forest';
  desc[3] := 'Tall dark trees. Paths lead in all directions.';
  SetEx(3, 4, 6, 7, 2);
  rname[4] := 'Cave mouth';
  desc[4] := 'A cave opens in a grey cliff. It is dark inside.';
  SetEx(4, 5, 0, 3, 0);
  rname[5] := 'Dark cave';
  desc[5] := 'A deep cave. A heavy iron door is set in the east wall.';
  SetEx(5, 0, 8, 4, 0);
  rname[6] := 'Riverbank';
  desc[6] := 'A fast river. A rope hangs from an old tree.';
  SetEx(6, 0, 0, 0, 3);
  rname[7] := 'Hill';
  desc[7] := 'A windy hill. You can see the whole valley.';
  SetEx(7, 3, 0, 0, 0);
  rname[8] := 'Treasure room';
  desc[8] := 'Gold and jewels glitter everywhere!';
  SetEx(8, 0, 0, 0, 5);
  iname[1] := 'lamp';
  iloc[1] := 1;
  iname[2] := 'key';
  iloc[2] := 7;
  iname[3] := 'rope';
  iloc[3] := 6;
  iname[4] := 'gold';
  iloc[4] := 8
end;

procedure Look;
var j: integer; any: boolean;
begin
  TextColor(14);
  writeln(rname[room]);
  TextColor(7);
  writeln(desc[room]);
  any := false;
  for j := 1 to nitems do
    if iloc[j] = room then
    begin
      if not any then write('You see: ');
      write(iname[j], ' ');
      any := true
    end;
  if any then writeln;
  write('Exits:');
  if ex[room, 1] > 0 then write(' north');
  if ex[room, 2] > 0 then write(' east');
  if ex[room, 3] > 0 then write(' south');
  if ex[room, 4] > 0 then write(' west');
  writeln
end;

procedure Go(dir: integer);
var t: integer;
begin
  t := ex[room, dir];
  if t = 0 then writeln('You cannot go that way.')
  else if (t = 5) and (iloc[1] <> carried) then
    writeln('It is far too dark to enter without a light.')
  else if (t = 8) and (iloc[2] <> carried) then
    writeln('The iron door is locked. You need a key.')
  else
  begin
    room := t;
    moves := moves + 1;
    Look
  end
end;

function Find(n: sstr): integer;
var j, r: integer;
begin
  r := 0;
  for j := 1 to nitems do
    if iname[j] = n then r := j;
  Find := r
end;

procedure Take(n: sstr);
var k: integer;
begin
  k := Find(n);
  if k = 0 then writeln('I see no such thing.')
  else if iloc[k] = carried then writeln('You already have it.')
  else if iloc[k] <> room then writeln('It is not here.')
  else
  begin
    iloc[k] := carried;
    writeln('Taken.');
    if k = 4 then
    begin
      TextColor(10);
      writeln('You grab the gold. YOU WIN in ', moves, ' moves!');
      done := true
    end
  end
end;

procedure Drop(n: sstr);
var k: integer;
begin
  k := Find(n);
  if (k = 0) or (iloc[k] <> carried) then writeln('You do not have that.')
  else
  begin
    iloc[k] := room;
    writeln('Dropped.')
  end
end;

procedure Inventory;
var j: integer; any: boolean;
begin
  any := false;
  write('You carry:');
  for j := 1 to nitems do
    if iloc[j] = carried then
    begin
      write(' ', iname[j]);
      any := true
    end;
  if not any then write(' nothing');
  writeln
end;

function Dir(w: sstr): integer;
begin
  Dir := 0;
  if (w = 'n') or (w = 'north') then Dir := 1;
  if (w = 'e') or (w = 'east') then Dir := 2;
  if (w = 's') or (w = 'south') then Dir := 3;
  if (w = 'w') or (w = 'west') then Dir := 4
end;

procedure Parse;
var p: integer;
begin
  for p := 1 to length(cmd) do
    if (cmd[p] >= 'A') and (cmd[p] <= 'Z') then cmd[p] := chr(ord(cmd[p]) + 32);
  p := pos(' ', cmd);
  if p = 0 then
  begin
    verb := cmd;
    noun := ''
  end
  else
  begin
    verb := copy(cmd, 1, p - 1);
    noun := copy(cmd, p + 1, 20)
  end
end;

begin
  ClrScr;
  Init;
  room := 1;
  moves := 0;
  done := false;
  TextColor(10);
  writeln('*** THE LOST TREASURE ***');
  TextColor(7);
  writeln('Find the gold. Type help for commands.');
  writeln;
  Look;
  repeat
    writeln;
    write('> ');
    readln(cmd);
    Parse;
    if verb = 'go' then d := Dir(noun) else d := Dir(verb);
    if d > 0 then Go(d)
    else if (verb = 'look') or (verb = 'l') then Look
    else if (verb = 'take') or (verb = 'get') then Take(noun)
    else if verb = 'drop' then Drop(noun)
    else if (verb = 'inv') or (verb = 'i') then Inventory
    else if verb = 'help' then
      writeln('n e s w, go, look, take, drop, inv, quit')
    else if (verb = 'quit') or (verb = 'q') then done := true
    else if length(verb) > 0 then writeln('I do not understand.')
  until done
end.
