{ Public domain: do whatever you like with this file. Only tested in the VICE emulator. Enjoy! }
program checkers;
{ Checkers (draughts) for the 64Pascal compiler.
  You play 'o' (white, moving up the screen), the computer plays 'x' (moving down).
  Kings are shown as capitals. Captures are compulsory and a piece must keep jumping
  while it can (a man that reaches the last row becomes a king and stops).
  Enter a move as from-square and to-square, for example  c3d4  (or c3 d4).
  Q quits. Written without real numbers or pointers, so it compiles on every machine.
  On the Plus/4 compile it to disk (CTRL+C): it is too big to run from the editor. }
uses Crt;

type
  TBoard = array[1..8, 1..8] of integer;

var
  board, save: TBoard;          { 0 empty, 1 / 2 your man / king, -1 / -2 computer man / king }
  pv: array[1..4] of integer;   { the four values read from a typed move }
  chainR, chainC: integer;      { the piece that must go on jumping (0 = none) }
  mr1, mc1, mr2, mc2: integer;  { the move being tried: from row, column, to row, column }
  lr1, lc1, lr2, lc2: integer;  { the computer's last move, for the message }
  found: boolean;               { FindBest found a move }
  jumped, promoted: boolean;    { what DoMove did }
  quit, over: boolean;
  turn, moves, nh, nc: integer; { whose turn (1 = you, -1 = computer), move counter, pieces left }
  msg: string[40];
  inp: string[30];

{ ---- the rules ---------------------------------------------------------------------------- }

function Owner(p: integer): integer;     { 1 = you, -1 = computer, 0 = empty }
begin
  if p > 0 then Owner := 1
  else if p < 0 then Owner := -1
  else Owner := 0
end;

function Inb(r, c: integer): boolean;    { is the square on the board? }
begin
  Inb := (r >= 1) and (r <= 8) and (c >= 1) and (c <= 8)
end;

function Fwd(p, dr: integer): boolean;   { may piece p move in the row direction dr? }
begin
  if (p = 2) or (p = -2) then Fwd := true
  else Fwd := (dr = -Owner(p))           { men only move forward: you up (-1), the computer down (+1) }
end;

function JumpOK(r, c, dr, dc: integer): boolean;   { can the piece at r,c jump over r+dr,c+dc? }
var p, r2, c2: integer;
begin
  JumpOK := false;
  p := board[r, c];
  r2 := r + 2 * dr;
  c2 := c + 2 * dc;
  if Inb(r2, c2) and Fwd(p, dr) then
    if board[r2, c2] = 0 then
      if Owner(board[r + dr, c + dc]) = -Owner(p) then JumpOK := true
end;

function StepOK(r, c, dr, dc: integer): boolean;   { can the piece at r,c step to r+dr,c+dc? }
var r2, c2: integer;
begin
  StepOK := false;
  r2 := r + dr;
  c2 := c + dc;
  if Inb(r2, c2) and Fwd(board[r, c], dr) then
    if board[r2, c2] = 0 then StepOK := true
end;

function PieceJumps(r, c: integer): boolean;       { has the piece at r,c a capture? }
var i, j: integer;
begin
  PieceJumps := false;
  for i := 0 to 1 do
    for j := 0 to 1 do
      if JumpOK(r, c, 2 * i - 1, 2 * j - 1) then PieceJumps := true
end;

function PieceSteps(r, c: integer): boolean;       { has the piece at r,c a plain step? }
var i, j: integer;
begin
  PieceSteps := false;
  for i := 0 to 1 do
    for j := 0 to 1 do
      if StepOK(r, c, 2 * i - 1, 2 * j - 1) then PieceSteps := true
end;

function SideJumps(o: integer): boolean;           { has side o a capture anywhere? }
var r, c: integer;
begin
  SideJumps := false;
  for r := 1 to 8 do
    for c := 1 to 8 do
      if Owner(board[r, c]) = o then
        if PieceJumps(r, c) then SideJumps := true
end;

function SideMoves(o: integer): boolean;           { can side o move at all? }
var r, c: integer;
    res: boolean;                        { (the name of a function cannot be read inside it) }
begin
  res := SideJumps(o);
  if not res then
    for r := 1 to 8 do
      for c := 1 to 8 do
        if Owner(board[r, c]) = o then
          if PieceSteps(r, c) then res := true;
  SideMoves := res
end;

{ Legal: is r1,c1 -> r2,c2 a legal move for side o? Captures are compulsory, and while a piece
  is in the middle of a multiple jump (chainR / chainC) only that piece may jump. }
function Legal(o, r1, c1, r2, c2: integer): boolean;
var dr, dc, ar, ac, sr, sc: integer;
begin
  Legal := false;
  if Inb(r1, c1) and Inb(r2, c2) then
    if Owner(board[r1, c1]) = o then
      if board[r2, c2] = 0 then
      begin
        dr := r2 - r1;
        dc := c2 - c1;
        ar := dr;
        if ar < 0 then ar := -ar;
        ac := dc;
        if ac < 0 then ac := -ac;
        sr := 1;
        if dr < 0 then sr := -1;
        sc := 1;
        if dc < 0 then sc := -1;
        if ar = ac then
        begin
          if ar = 1 then
          begin
            if chainR = 0 then
              if not SideJumps(o) then
                if StepOK(r1, c1, dr, dc) then Legal := true
          end
          else if ar = 2 then
          begin
            if (chainR = 0) or ((chainR = r1) and (chainC = c1)) then
              if JumpOK(r1, c1, sr, sc) then Legal := true
          end
        end
      end
end;

{ DoMove: make the move on the board (it must be legal). Sets jumped and promoted. }
procedure DoMove(r1, c1, r2, c2: integer);
var p, ar: integer;
begin
  p := board[r1, c1];
  board[r1, c1] := 0;
  board[r2, c2] := p;
  ar := r2 - r1;
  if ar < 0 then ar := -ar;
  jumped := ar = 2;
  if jumped then board[(r1 + r2) div 2, (c1 + c2) div 2] := 0;
  promoted := false;
  if (p = 1) and (r2 = 1) then
  begin
    board[r2, c2] := 2;
    promoted := true
  end;
  if (p = -1) and (r2 = 8) then
  begin
    board[r2, c2] := -2;
    promoted := true
  end
end;

{ Attacked: could the piece of side o on r,c be captured right now? }
function Attacked(r, c, o: integer): boolean;
var i, j, dr, dc, ar, ac, br, bc: integer;
begin
  Attacked := false;
  for i := 0 to 1 do
    for j := 0 to 1 do
    begin
      dr := 2 * i - 1;
      dc := 2 * j - 1;
      ar := r + dr;
      ac := c + dc;
      br := r - dr;
      bc := c - dc;
      if Inb(ar, ac) and Inb(br, bc) then
        if Owner(board[ar, ac]) = -o then
          if Fwd(board[ar, ac], -dr) then
            if board[br, bc] = 0 then Attacked := true
    end
end;

{ ---- the computer player ------------------------------------------------------------------- }

{ FindBest: look at every legal move of side o, try it on the board and score it:
  captures and promotions are good, ending up where the opponent can capture is bad.
  The best move is left in mr1, mc1, mr2, mc2 (found = false when there is none). }
procedure FindBest(o: integer);
var r, c, i, j, k, dr, dc, r2, c2, sc, best: integer;
begin
  best := -10000;
  found := false;
  for r := 1 to 8 do
    for c := 1 to 8 do
      if Owner(board[r, c]) = o then
        for k := 1 to 2 do
          for i := 0 to 1 do
            for j := 0 to 1 do
            begin
              dr := (2 * i - 1) * k;
              dc := (2 * j - 1) * k;
              r2 := r + dr;
              c2 := c + dc;
              if Legal(o, r, c, r2, c2) then
              begin
                save := board;
                DoMove(r, c, r2, c2);
                sc := 0;
                if jumped then sc := sc + 10;
                if promoted then sc := sc + 6;
                if Attacked(r2, c2, o) then sc := sc - 9;
                if o = -1 then sc := sc + r2 - r else sc := sc + r - r2;
                if (c2 = 1) or (c2 = 8) then sc := sc + 1;
                if (o = -1) and (r = 1) then sc := sc - 1;
                if (o = 1) and (r = 8) then sc := sc - 1;
                board := save;
                sc := sc * 8 + (r * 3 + c * 5 + moves) mod 8;   { varies the choice between equal moves }
                if sc > best then
                begin
                  best := sc;
                  found := true;
                  mr1 := r;
                  mc1 := c;
                  mr2 := r2;
                  mc2 := c2
                end
              end
            end
end;

{ ---- screen and input ---------------------------------------------------------------------- }

procedure Cell(p, r, c: integer);        { write one square (3 characters) }
begin
  if p = 0 then
  begin
    TextColor(7);
    if (r + c) mod 2 = 0 then write(' . ') else write('   ')
  end
  else
  begin
    if p > 0 then TextColor(1) else TextColor(2);
    if p = 1 then write(' o ');
    if p = 2 then write(' O ');
    if p = -1 then write(' x ');
    if p = -2 then write(' X ')
  end
end;

procedure Draw;
var r, c: integer;
begin
  ClrScr;
  TextColor(1);
  GotoXY(1, 1);
  write('CHECKERS   you: o   computer: x');
  for r := 1 to 8 do
  begin
    GotoXY(1, r + 2);
    TextColor(1);
    write(9 - r);
    for c := 1 to 8 do Cell(board[r, c], r, c)
  end;
  GotoXY(1, 11);
  TextColor(1);
  write('  a  b  c  d  e  f  g  h');
  nh := 0;
  nc := 0;
  for r := 1 to 8 do
    for c := 1 to 8 do
    begin
      if board[r, c] > 0 then nh := nh + 1;
      if board[r, c] < 0 then nc := nc + 1
    end;
  GotoXY(1, 13);
  write('you ', nh, '   computer ', nc);
  GotoXY(1, 15);
  write(msg)
end;

function Parse: boolean;                 { read a move from inp into mr1, mc1, mr2, mc2 }
var i, n: integer;
    ch: char;
    ok: boolean;
begin
  n := 0;
  ok := true;
  for i := 1 to length(inp) do
  begin
    ch := upcase(inp[i]);
    if n >= 4 then
    begin
      if ch <> ' ' then ok := false
    end
    else if n mod 2 = 0 then
    begin
      if (ch >= 'A') and (ch <= 'H') then
      begin
        n := n + 1;
        pv[n] := ord(ch) - 64
      end
      else if ch <> ' ' then ok := false
    end
    else
    begin
      if (ch >= '1') and (ch <= '8') then
      begin
        n := n + 1;
        pv[n] := 9 - (ord(ch) - 48)
      end
      else if ch <> ' ' then ok := false
    end
  end;
  if n <> 4 then ok := false;
  mc1 := pv[1];
  mr1 := pv[2];
  mc2 := pv[3];
  mr2 := pv[4];
  Parse := ok
end;

procedure HumanTurn;
var done, ok: boolean;
begin
  chainR := 0;
  chainC := 0;
  done := false;
  repeat
    Draw;
    GotoXY(1, 17);
    TextColor(1);
    write('Your move (e.g. c3d4, Q = quit): ');
    readln(inp);
    if (length(inp) > 0) and (upcase(inp[1]) = 'Q') then
    begin
      quit := true;
      done := true
    end
    else
    begin
      ok := Parse;
      if ok then ok := Legal(1, mr1, mc1, mr2, mc2);
      if ok then
      begin
        DoMove(mr1, mc1, mr2, mc2);
        msg := '';
        if jumped and (not promoted) and PieceJumps(mr2, mc2) then
        begin
          chainR := mr2;                 { it must go on jumping with the same piece }
          chainC := mc2;
          msg := 'Jump again with the same piece'
        end
        else done := true
      end
      else if chainR <> 0 then msg := 'You must keep jumping'
      else if SideJumps(1) then msg := 'You must capture'
      else msg := 'Not a legal move'
    end
  until done;
  chainR := 0;
  chainC := 0
end;

procedure ComputerTurn;
var done: boolean;
begin
  chainR := 0;
  chainC := 0;
  done := false;
  repeat
    FindBest(-1);
    if not found then done := true
    else
    begin
      if chainR = 0 then
      begin
        lr1 := mr1;
        lc1 := mc1
      end;
      lr2 := mr2;
      lc2 := mc2;
      DoMove(mr1, mc1, mr2, mc2);
      if jumped and (not promoted) and PieceJumps(mr2, mc2) then
      begin
        chainR := mr2;
        chainC := mc2
      end
      else done := true
    end
  until done;
  chainR := 0;
  chainC := 0;
  msg := 'I moved ';
  msg := msg + chr(64 + lc1) + chr(48 + 9 - lr1) + ' to ' + chr(64 + lc2) + chr(48 + 9 - lr2)
end;

procedure Setup;
var r, c: integer;
begin
  for r := 1 to 8 do
    for c := 1 to 8 do
    begin
      board[r, c] := 0;
      if (r + c) mod 2 = 0 then
      begin
        if r <= 3 then board[r, c] := -1;
        if r >= 6 then board[r, c] := 1
      end
    end;
  chainR := 0;
  chainC := 0;
  turn := 1;
  moves := 0;
  quit := false;
  over := false;
  msg := 'You start'
end;

begin
  Setup;
  repeat
    if not SideMoves(turn) then over := true
    else
    begin
      if turn = 1 then HumanTurn else ComputerTurn;
      turn := -turn;
      moves := moves + 1
    end
  until over or quit;
  Draw;
  GotoXY(1, 17);
  TextColor(1);
  if quit then write('Bye')
  else if turn = 1 then write('You cannot move: the computer wins')
  else write('The computer cannot move: you win!');
  writeln
end.
