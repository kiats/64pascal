# TODO

Note: some of these things will maybe never be implemented. Every feature eats up memory of the computer (in the compiler, in the
runtime and in the programs it makes), and the memory is small, especially on the Plus/4 and the C128. We need a compromise:
what goes in is decided case by case, by what it costs.

And the other way round: maybe some functionality will be removed again, to make the compiler and the programs smaller. But who knows :)

## Language
- nested procedures and functions
- `with`
- `goto` and `label`
- enumerated types
- subrange types
- `set of` and `in`
- typed constants
- variant records
- `word`, `longint`, `shortint`
- `shl` / `shr` with a variable count
- procedural types
- more than 8 parameters
- functions that return a string
- writable string value parameters
- `'literal':w`
- `forward` definitions without the parameter list
- `packed`
- `Hi`, `Lo`, `Low`, `High`, `SizeOf`
- `FillChar`, `Move`, `Concat`, `Swap`
- `Peek`, `Poke`
- `Halt(n)` with an exit code
- real `unit` / `interface` / `implementation`

## Files
- `Assign`, `Reset`, `Rewrite`, `Close`
- `Eof`
- `ReadLn(f)`, `WriteLn(f)`, `Read(f)`, `Write(f)`
- `text`, `file`, typed files

## Units
- Graph unit
- sound
- sprites

## IDE
- find and replace
- block operations (mark, copy, move, delete)
- undo
- jump to a line number
- syntax colours
- bigger text on the C128
- run programs with real / pointers / `:w` from the editor on the Plus/4
- compile to disk without leaving the editor, then run the file

## Platforms
- test on real hardware
- Plus/4: more room for programs that are run from the editor
- Plus/4: more room for globals and the heap
- Plus/4: a bigger text area in the IDE
- C128: a bigger source buffer in the simple compiler and the IDE
- C128: 80 column screen for the IDE
- C128: use the other RAM bank for text
- C16 / C116 (16 KB)
- PET and VIC-20
- C64 Ultimate: REU, turbo mode (see ULTIMATE.md)

## Compiler
- compare the header of a `forward` definition with its declaration
- refuse a string constant as a `var` parameter
- loops nested more than 8 deep
- a bigger symbol table on the C128
- better error messages (more codes, the name of the identifier)
- range checks
- warnings for unused variables
- smaller generated code (peephole optimizer)
- slimmer compiler: a `SLIM` build without `real`, pointers, `write(x:w)` and `Random` (no extension chunks)
- slimmer compiler: leave out compiler directives (`{$IFDEF}` ...) in a slim build
- slimmer compiler: more shared code for sequences that repeat (the `err_*`, `lookup_must` and `gc_*` helpers are the start)
- slimmer compiler: table driven built-in routines
- slimmer compiler: remove rarely used functionality
- full regression run (all tests/ programs on all three machines) after the slimming of the compiler
- link only the runtime routines that are used, not whole chunks
- faster compile

## Runtime
- smaller core runtime
- more Crt routines (window, Sound, ReadKey for function keys on every machine)
- faster `real` routines

## Tests and tools
- automatic test run for all programs in tests/ on all three machines
- a test program for every language feature (ctl1.pas is the start)
- expected output next to every test program
- compare results of the three machines

## Documentation
- tutorial for the language
- list of all built-in routines
- notes for building and running on Linux and macOS
