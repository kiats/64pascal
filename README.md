# 64Pascal

A Turbo Pascal style Pascal compiler and editor for the Commodore 64, the Commodore 128 and the Commodore Plus/4. It runs on
the machine itself (no PC needed to compile), it is written in 6502 assembly, and the programs it produces are small
stand-alone `.prg` files that run on a bare machine.

> **Public domain.** Do whatever you like with it: use it, change it, share it, sell it. No permission, credit or payment
> needed. It comes as it is, with no warranty.
>
> **Only tested in the VICE emulator.** Nobody has tried it on real hardware yet, so please be gentle, and tell us what you find.
>
> **Made for the C64 first.** The Commodore 64 is the main target and the best tested. The C128 and Plus/4 versions are there
> and work, but they have not been tested nearly as much, so expect more rough edges on them.

> **Big programs: do not use the IDE.** The IDE keeps the editor, the compiler and the text in memory at the same time, so
> there is little room left for the text. For a bigger source, edit it with `64edit` (the editor alone has the most room for
> text) and compile it with `64pascal` (the simple compiler has the biggest source buffer). Use the IDE for small programs,
> where writing, running and fixing errors in one place is handy. How big "big" is on each machine is in
> [differences.md](differences.md).

## What you get

Three programs, built from the same sources, for each of the three machines:

| Program | What it is |
|---|---|
| `64ide` | The IDE: a full screen editor and the compiler in one program. Write, compile, run and fix errors without leaving it. |
| `64pascal` | The simple compiler: you give it the name of a source file on the disk, it writes a stand-alone program and offers to run it. |
| `64edit` | The editor alone, without the compiler, so there is more room for the text (about 46 KB on the C64). |

A compiled program is a normal BASIC-started `.prg` (a "Hello, world" is under 1 KB). It contains only the runtime routines it
really uses and needs neither the compiler nor the IDE.

## The language

The compiler is a single pass compiler that writes machine code directly. It understands most of Turbo Pascal:

- `program`, `uses` (the Crt unit is built in), `const`, `type`, `var`, `absolute` variables
- `integer` (16 bit), `byte`, `char`, `boolean`, `real` (software floating point, about 7 digits)
- arrays (any ordinal index range, several dimensions), strings (`string`, `string[n]`), records, pointers (`New`, `Dispose`)
- procedures and functions with value and `var` parameters, locals and recursion; `forward` declarations; nested procedures
  and functions (up to 4 levels deep, they can use the variables of the routines around them)
- `if`, `while`, `repeat`, `for`, `case` (with ranges and `else`), `Exit`, `Break`, `Continue`, `Halt`
- `Inc`, `Dec`, `Odd`, `Succ`, `Pred`, `shl`, `shr`, string constants
- `write` / `writeln` with `:width` and `:width:decimals`, `read` / `readln`, `Str`, `Val`, `Random`
- the usual string and number routines (`Length`, `Copy`, `Pos`, `UpCase`, `Chr`, `Ord`, `Delete`, `Insert`, `Trunc`, `Round`,
  `Abs`, `Sqr`, `Sqrt`, `Sin`, `Cos`, `ArcTan`, `Exp`, `Ln`, `Int`, `Frac`, `Pi`)
- Crt: `ClrScr`, `GotoXY`, `TextColor`, `TextBackground`, `ReadKey`, `KeyPressed`, `Delay`, ...
- conditional compilation: `{$IFDEF C64}`, `{$IFDEF C128}`, `{$IFDEF PLUS4}`, `{$DEFINE x}`, ...

Not there yet (see `todo.md`): `with`, sets, enumerated and subrange types, units, files.

```pascal
program hello;
var i: integer;
begin
  for i := 1 to 3 do
    writeln('Hello from 64Pascal, round ', i)
end.
```

The folder `tests/` has many more programs, including a text adventure (`textgame.pas`) and a game of checkers
(`checkers.pas`).

## Building the programs

There are no ready made releases: you build the programs yourself, which takes a few seconds. You need

- **Java** (any reasonably recent version) to run the assembler,
- **[Kick Assembler](http://theweb.dk/KickAssembler)** (version 5.25 was used; the `KickAss.jar` file),
- an emulator to run the result, for example **[VICE](https://vice-emu.sourceforge.io)** (`x64sc`, `x128`, `xplus4`).

Kick Assembler and VICE are third party programs with their own licences; this project does not change them.

The general form of the command, run from the folder of this project, is

```
java -jar KickAss.jar src/<program>.asm [-define <NAME>] ... -o <output>.prg
```

`-define` chooses the machine and the variant. Without it the C64 version is built.

| Program | Source file | C64 | C128 (128 mode) | Plus/4 |
|---|---|---|---|---|
| IDE | `src/64ide.asm` | `-define IDE` | `-define IDE -define C128` | `-define IDE -define PLUS4` |
| Simple compiler | `src/64pascal.asm` | (nothing) | `-define C128` | `-define PLUS4` |
| Editor alone | `src/64edit.asm` | (nothing) | `-define C128` | `-define PLUS4` |

For example the C64 IDE, and the Plus/4 simple compiler:

```
java -jar KickAss.jar src/64ide.asm -define IDE -o 64ide_c64.prg
java -jar KickAss.jar src/64pascal.asm -define PLUS4 -o 64pascal_plus4.prg
```

Things to know:

- The C128 in C64 mode runs the C64 programs.
- The assembler checks that everything fits the memory map of the machine (the lines `Made n asserts, 0 failed`). If you add
  code and an assert fails, the program has grown out of its space; `CLAUDE.md` explains the memory maps.
- `-vicesymbols` makes the assembler write a symbol file that the VICE monitor can load, which helps when debugging.
- `src/main.asm` is a small test harness that compiles one embedded program (`:src=file.pas` picks the program); it is only
  for working on the compiler.

## Running them

Put the program and some Pascal sources on a disk image, attach the image to the emulator as drive 8 and load the program.
With the tools that come with VICE:

```
c1541 -format "pascal,01" d64 pascal.d64 -write 64ide_c64.prg 64ide -write tests/proc.pas proc.pas
x64sc -8 pascal.d64 -autostart 64ide_c64.prg
```

Use `x128` for the C128 and `xplus4` for the Plus/4. Then it is the same as on the real machine: `LOAD"64IDE",8` and `RUN`
(the autostart does this for you). Give the files on the disk lower case names when you write them with `c1541`; they then
have the letters that you get when you type unshifted letters on the machine.

### The IDE keys

| | C64 / C128 | Plus/4 |
|---|---|---|
| Save | F2 | CTRL+S |
| Open (empty name lists the `.pas` files) | F3 | CTRL+L |
| Autosave, compile and run | F5 | CTRL+R |
| Compile to a stand-alone file on disk | F4 | CTRL+C |
| Compile and run without the autosave | F6 | ESC then X |
| Page down / up | F7 / F8 | ESC then D / U |
| Quit (twice if the text is not saved) | RUN/STOP | RUN/STOP |

The cursor keys, HOME, SHIFT+HOME (start of the text), CTRL+E (end of the line), DEL, SHIFT+DEL and RETURN (keeps the
indentation) work as you would expect. The text is saved to `NAME.A` and `NAME.B` alternately before every run, so a crash does
not lose your work. A compile error puts the cursor on the line and shows the message.

### The simple compiler

`64pascal` asks for the name of the source file (RETURN alone lists the `.pas` files on the disk), compiles it, saves the
program under the same name without `.pas` and asks if you want to run it now.

## Differences between the machines

The three machines have very different memory, so there are differences: how big a text or a program can be, and on the Plus/4
the keys. They are all listed in [differences.md](differences.md). The short version:

- **C64**: everything works.
- **C128**: everything works, in 128 mode with the 40 column screen; the text and source buffers are smaller.
- **Plus/4**: everything works as well, but the text area is smaller (about 17 KB in the IDE, about 26 KB in `64pascal`) and
  a program that is run from the editor must be small and may not use `real`, pointers or `:w` (compile such a program to disk
  with CTRL+C instead).

## Testing

`tests/` holds Pascal programs. `run_simple_test.sh`, `run_standalone_test.sh`, `tools/ptest.sh`, `tools/ide_test.sh`,
`tools/ide_test_plus4.sh` and `tools/p4run.sh` compile and run them in VICE and save a screenshot (they need Git Bash or a
similar shell on Windows, and Python for some of them).

## Where things are

| | |
|---|---|
| `src/` | the sources: the compiler (`compiler.asm` and the files it includes), the runtime (`runtime.asm`), the editor (`editor.asm`), the IDE (`64ide.asm`), the simple compiler (`64pascal.asm`) |
| `tests/` | Pascal test programs |
| `tools/` | helper scripts for testing |
| `DESIGN.md` | the design |
| `CLAUDE.md` | notes about the code and its pitfalls, for anyone who wants to work on it |
| `differences.md` | what is different on each machine |
| `todo.md` | what is still missing |
| `ULTIMATE.md` | ideas for the C64 Ultimate |

Every source file starts with a short note about the public domain and the VICE-only testing. The code is commented so that a
person can read it: every file says what it is for, and every routine says what it takes and returns.

## Help wanted

Real hardware tests, bug reports, new test programs and the items in `todo.md` are all very welcome. Have fun!
