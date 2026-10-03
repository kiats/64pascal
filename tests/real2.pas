{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program real2;
begin
  writeln(sqrt(16.0):0:6);
  writeln(sqrt(0.25):0:6);
  writeln(exp(1.0):0:6);
  writeln(exp(-1.0):0:6);
  writeln(exp(10.0):0:2);
  writeln(ln(2.718282):0:6);
  writeln(ln(10.0):0:6);
  writeln(ln(0.5):0:6);
  writeln(sin(1.0):0:6);
  writeln(cos(1.0):0:6);
  writeln(sin(3.0):0:6);
  writeln(cos(3.0):0:6);
  writeln(arctan(1.0):0:6);
  writeln(arctan(2.0):0:6);
  writeln(arctan(-0.3):0:6);
  writeln(pi:0:6);
  writeln(frac(3.75):0:3, ' ', int(-3.75):0:1, ' ', abs(-2.5):0:1, ' ', sqr(1.5):0:2);
  writeln(1e10);
  writeln(1.5e-5);
  writeln(123456.789:0:2);
  writeln(trunc(1234.9), ' ', round(0.5), ' ', round(-0.5), ' ', abs(-7), ' ', sqr(9));
  writeln(1/3);
  writeln(-2.5E3)
end.
