{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program casetest;
var i, n: integer; c: char;
begin
  for i := 0 to 12 do
  begin
    case i of
      0: write('zero ');
      1, 2, 3: write('small ');
      4..6: begin write('mid '); write(i) end;
      10: write('ten ')
    else
      write('other ')
    end;
    write(',')
  end;
  writeln;
  c := 'b';
  case c of
    'a': writeln('A');
    'b', 'c': writeln('B or C')
  end;
  n := -5;
  case n of
    -5: writeln('minus five');
    5: writeln('five')
  end;
  case n of 1: writeln('no') end;
  writeln('done')
end.
