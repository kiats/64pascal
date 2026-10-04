{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program n7;
type pint = ^integer;

function f(x: integer; var y: integer; r: real): integer;
  procedure setit;
  begin
    y := y + x;
    inc(y);
    dec(y, 2)
  end;
  function twice: integer;
  begin
    twice := x * 2
  end;
  procedure showr;
  begin
    writeln(r:0:2)
  end;
begin
  setit;
  showr;
  f := twice + y
end;

procedure a1;
  var base: integer;
  procedure b1(k: integer);
  begin
    writeln('b1 ', base + k)
  end;
  procedure c1;
    procedure d1;
    begin
      b1(1);
      base := base + 10
    end;
  begin
    d1
  end;
begin
  base := 100;
  c1;
  b1(2)
end;

procedure pe;
  var p: pint;
      s: string[20];
  procedure mk;
  begin
    new(p);
    p^ := 42;
    s := 'abc'
  end;
begin
  mk;
  writeln(p^, ' ', s)
end;

procedure fx;
  procedure inner2; forward;
  procedure inner1(n: integer);
  begin
    if n > 0 then
    begin
      writeln('i1 ', n);
      inner2
    end
  end;
  procedure inner2;
  begin
    writeln('i2');
    exit;
    writeln('not shown')
  end;
  var v: integer;
begin
  v := 7;
  inner1(1);
  writeln(v)
end;

procedure lp;
  procedure run;
  var i: integer;
  begin
    for i := 1 to 5 do
    begin
      if i = 2 then continue;
      if i = 4 then break;
      write(i, ' ')
    end;
    writeln
  end;
begin
  run
end;

var y1: integer;
begin
  y1 := 10;
  writeln(f(5, y1, 2.5), ' ', y1);
  a1;
  pe;
  fx;
  lp
end.
