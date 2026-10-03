# Differences between the C64, C128 and Plus/4 versions

Keep this file up to date: change it whenever a feature, a memory limit or a key differs between the machines
(see CLAUDE.md). "C128" means 128 mode; the C128 in C64 mode uses the C64 programs. Sizes come from `src/memmap.asm`
and from fresh builds (bytes of text / source that fit in the buffer; they change a little whenever the compiler grows or
shrinks, because the buffer starts right behind the program).

| | C64 | C128 (128 mode) | Plus/4 |
|---|---|---|---|
| Programs | `64pascal`, `64ide`, `64edit` | `64pascal`, `64ide`, `64edit` | `64pascal`, `64ide`, `64edit` |
| Memory while the compiler runs | ROMs on (BASIC off, KERNAL on) | ROMs on, MMU bank 0 | ROMs off, interrupts off (`HIROM`) |
| KERNAL calls | direct | direct, `SETBANK` for file names | through the `KF_` stubs (`kfstubs.asm`), ROM on for one call |
| Where the source text lives | low RAM, inside the dead program image | low RAM, inside the dead program image | RAM under the ROMs: `$8D00`-`$D2F0` in `64ide` (the editor itself is at `$8000`), `$8000`-`$E9F0` in `64pascal` |
| Source text, `64ide` | about 10.7 KB | about 6.7 KB | about 17.5 KB |
| Source buffer, `64pascal` | about 13.5 KB | about 6.7 KB | about 26.5 KB |
| Text, `64edit` (no compiler) | about 46 KB | about 37 KB | about 24 KB |
| Program run from the editor | in memory behind the text, up to `$8000` | in memory behind the text, up to `$8400` | in low RAM `$5200`-`$6400`, about 4.5 KB, only programs without real / pointers / `:w` (others: compile to disk) |
| "Run now" in `64pascal` | compiles again and runs in memory | same | starts the compiled file image (copied to `$1001`), any program |
| Standalone `.prg` output | yes | yes | yes, built in the high RAM; the image must stay below `$4c00` (about 15 KB) when it uses real / pointers / `:w`, else below `$6400` |
| Program globals (and heap) | 4 KB | 2 KB | 1 KB |
| Software stack | 2.75 KB | 1.75 KB | 0.75 KB |
| Compiler symbol table | 7 KB | 3 KB | 4 KB |
| `real`, `Trunc`, `Round`, `Abs`, `Sqr`, `Sqrt`, `Sin`, `Cos`, `Arctan`, `Exp`, `Ln`, `Int`, `Frac`, `Pi` | yes | yes | yes in `64ide` / `64pascal` (not in the `main.asm` test harness or `64edit`) |
| `Random` / `Randomize` | yes | yes | yes (as above) |
| Pointers (`^T`, `New`, `Dispose`, `nil`, `@`) | yes | yes | yes (as above) |
| `write(x:w)` and `Str(x:w:d)` | yes | yes | yes (as above) |
| Crt unit, strings, records, arrays, `case` | yes | yes | yes |
| `Exit`, `Break`, `Continue`, `Halt`, `Inc`, `Dec`, `Odd`, `Succ`, `Pred`, `shl`, `shr`, `forward`, string constants | yes | yes | yes |
| Command keys | F2 / F3 / F4 / F5 / F6 | F2 / F3 / F4 / F5 / F6 | CTRL+S / L / R / C (ESC + letter also works) |
| Screen | 40 columns | needs the 40-column screen | 40 columns, screen at `$0C00` |

Notes
- `Abs` is part of the real group, so it exists wherever `real` does (on the Plus/4 only in `64ide` / `64pascal`).
  `tests/checkers.pas` avoids it so that it also compiles with the old Plus/4 harness.
- A function name cannot be read inside the function on any machine (it compiles as a recursive call): use a local variable.
- Plus/4: programs that are too big for the small run area, or that use real / pointers / `:w`, must be compiled to disk
  (CTRL+C in the IDE, or `64pascal`, which can also run the result). The extension chunks (float, heap, write formats,
  about 6 KB) are kept in the RAM under the ROMs behind the text in `64ide`, which (together with the editor at `$8000`) is why its text area is 17.5 KB;
  `64pascal` reads them from its own program image and so has the full 26.5 KB. In `64ide` the source text plus the
  program image that CTRL+C builds must fit together in about 21 KB (`checkers.pas`, 12 KB of source, needs `64pascal`).
- Plus/4: the KERNAL's CHROUT does not preserve X and Y (the C64's does): keep loop counters in RAM around `putc`.
