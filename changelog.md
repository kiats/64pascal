# Changelog

The version number is in `src/version.txt`.

## 0.0.1 - 2026-10-03

Initial release.

### Programs
- `64ide`: full screen editor and compiler in one program, runs the program from the editor, jumps to compile errors, autosave
- `64pascal`: simple compiler, writes a stand-alone program to disk, offers to run it
- `64edit`: the editor alone, with room for a big text
- all three for the Commodore 64, the Commodore 128 (128 mode) and the Commodore Plus/4

### Language
- `program`, `uses`, `const`, `type`, `var`, `absolute`
- `integer`, `byte`, `char`, `boolean`, `real` (software floating point, about 7 digits)
- arrays, strings, records, pointers (`New`, `Dispose`)
- procedures and functions (value and `var` parameters, locals, recursion), `forward` declarations
- `if`, `while`, `repeat`, `for`, `case`, `Exit`, `Break`, `Continue`, `Halt`
- `Inc`, `Dec`, `Odd`, `Succ`, `Pred`, `shl`, `shr`, string constants
- `write`, `writeln` (with `:width` and `:width:decimals`), `read`, `readln`, `Str`, `Val`, `Random`
- string and number functions, the Crt unit, conditional compilation

### Output
- stand-alone `.prg` files that contain only the runtime routines they use

### Machines
- Plus/4: the compiler and the editor run with the ROMs off, in the RAM under them, so there is room for the text
- Plus/4: CTRL+S / L / R / C instead of the function keys, because they type text on that machine
- Plus/4: a program that uses `real`, pointers or `:w` is compiled to disk (CTRL+C) or with `64pascal`, not run from the editor
- the C64 is the main target and the best tested; the C128 and the Plus/4 are tested much less
- the differences between the machines are in `differences.md`

### Tests and tools
- test programs in `tests/`, among them a text adventure (`textgame.pas`) and checkers (`checkers.pas`)
- helper scripts for testing in VICE in `tools/` and the `run_*.sh` scripts

### Documentation
- `README.md`, `differences.md`, `todo.md`, `DESIGN.md`, `ULTIMATE.md` and `CLAUDE.md` (notes about the code for people who work on it)

### Not there yet
- see `todo.md`

### Notes
- only tested in the VICE emulator, never on real hardware
- public domain
