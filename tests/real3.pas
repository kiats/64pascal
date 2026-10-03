{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program real3;
const k = 2.5; neg = -0.5;
type vec = array[1..3] of real;
     rec = record a: real; n: integer end;
var v: vec; r: rec; x, y: real; i: integer;
function half(a: real): real; begin half := a / 2 end;
function avg(a, b: real): real; begin avg := (a + b) / 2 end;
function sq(n: integer): real; begin sq := n * n end;
procedure bump(var z: real); begin z := z + 1 end;
procedure show(a: real; n: integer); begin writeln(a:0:2, ' ', n) end;
begin
  writeln(k:0:2, ' ', neg:0:2);
  v[1] := 1.5; v[2] := v[1] * 2; v[3] := v[2] + k;
  writeln(v[1]:0:1, ' ', v[2]:0:1, ' ', v[3]:0:1);
  r.a := 3.25; r.n := 4; writeln(r.a * r.n:0:2);
  x := half(5); writeln(x:0:2);
  writeln(avg(1, 2):0:2);
  writeln(sq(12):0:1);
  y := 10; bump(y); bump(y); writeln(y:0:1);
  show(1, 2);
  show(2.75, 3);
  x := 0; for i := 1 to 10 do x := x + 0.1; writeln(x:0:6);
  if x > 0.99 then writeln('big') else writeln('small');
  if (x < 1.01) and (x > 0.99) then writeln('about 1');
  writeln(-x:0:2, ' ', abs(-x):0:2);
  x := 7; y := 2;
  writeln(x / y:0:3, ' ', trunc(x / y), ' ', round(x / y));
  writeln(x + 1:0:1, ' ', 1 + x:0:1, ' ', x - 1:0:1, ' ', 10 - x:0:1);
  writeln(2 * x:0:1, ' ', x * 2:0:1, ' ', 10 / 4:0:2)
end.
