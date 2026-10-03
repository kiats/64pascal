// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// tokens.asm - token, symbol, type and error constants (the part of defs.asm that needs no other code;
// syntax.asm of the editor alone imports just this file)
// =====================================================================================

.encoding "ascii"               // character literals in the compiler are plain ASCII

// ---- token codes -------------------------------------------------------------------
// The lexer (lexer.asm) leaves one of these in 'tok' for every token it reads.
.const TK_EOF     = 0           // end of source
.const TK_IDENT   = 1           // identifier, name is in idbuf
.const TK_NUM     = 2           // number, value is in tokval
.const TK_STR     = 3           // string literal, contents are in strbuf (length byte first)
// punctuation
.const TK_PLUS    = 4           // +
.const TK_MINUS   = 5           // -
.const TK_STAR    = 6           // *
.const TK_LPAR    = 7           // (
.const TK_RPAR    = 8           // )
.const TK_LBRK    = 9           // [
.const TK_RBRK    = 10          // ]
.const TK_SEMI    = 11          // ;
.const TK_COMMA   = 12          // ,
.const TK_DOT     = 13          // .
.const TK_COLON   = 14          // :
.const TK_ASSIGN  = 15          // :=
.const TK_DOTDOT  = 16          // ..
// relational operators: TK_EQ..TK_GE must stay contiguous, expr.asm tests the range
.const TK_EQ      = 17          // =
.const TK_NE      = 18          // <>
.const TK_LT      = 19          // <
.const TK_LE      = 20          // <=
.const TK_GT      = 21          // >
.const TK_GE      = 22          // >=
.const TK_SLASH   = 23          // /
.const TK_CARET   = 24          // ^  (pointer type / dereference)
.const TK_AT      = 25          // @  (address of)
.const TK_REALNUM = 26          // real literal: text is in numbuf (length byte first)
// reserved words (looked up in kwtab in lexer.asm)
.const TK_PROGRAM = 32
.const TK_VAR     = 33
.const TK_CONST   = 34
.const TK_BEGIN   = 35
.const TK_END     = 36
.const TK_IF      = 37
.const TK_THEN    = 38
.const TK_ELSE    = 39
.const TK_WHILE   = 40
.const TK_DO      = 41
.const TK_REPEAT  = 42
.const TK_UNTIL   = 43
.const TK_FOR     = 44
.const TK_TO      = 45
.const TK_DOWNTO  = 46
.const TK_DIV     = 47
.const TK_MOD     = 48
.const TK_AND     = 49
.const TK_OR      = 50
.const TK_NOT     = 51
.const TK_XOR     = 52
.const TK_PROCEDURE = 53
.const TK_FUNCTION  = 54
.const TK_ABSOLUTE  = 55
.const TK_TYPE      = 56
.const TK_ARRAY     = 57
.const TK_OF        = 58
.const TK_RECORD    = 59
.const TK_USES      = 60
.const TK_CASE      = 61
.const TK_SHL       = 62        // shl, shr: multiplicative operators with a constant shift count (ctlfn.asm)
.const TK_SHR       = 63

// ---- symbol kinds (byte 16 of a symbol record) -----------------------------------------
.const K_VAR   = 1              // variable; address field = its address in the data area
.const K_CONST = 2              // constant; address field = its value
.const K_TYPE  = 3              // type name; address field = type code (T_*)
.const K_PROC  = 4              // built-in procedure; address field = id (1 write, 2 writeln)
.const K_PROCU = 5              // user procedure: 18/19 = code address, 20 = parameter count,
                                //   21 = bit mask of var parameters, 22/23 = parameter types (2 bits each)
.const K_FUNC  = 6              // user function: like K_PROCU, type field = result type
.const K_LOCAL = 7              // local variable or value parameter: 18 = offset in the frame
.const K_VARPARAM = 8           // var parameter: 18 = offset of the cell holding the address
.const K_FIELD = 13              // record field (hidden from normal lookup): 17 type, 18/19 offset,
                                //   20 descriptor of the field type, 21 descriptor of the owning record
.const K_BFUNC = 11              // built-in function (Length, Copy, ...): field 18 = routine number
.const K_BPROC = 12              // built-in procedure with arguments (Delete, Insert, Str)
.const K_CPARAM = 10            // read-only value parameter of array/string type, passed by address
.const K_VARB  = 9              // global variable stored in ONE byte (type byte, or absolute char/boolean)

// ---- value types (byte 17 of a symbol record, and 'etype' while compiling expressions) ---
.const T_INT  = 0               // 16-bit signed integer
.const T_BOOL = 1               // boolean, 0 or 1 in a 16-bit cell
.const T_CHAR = 2               // character, ASCII code in a 16-bit cell
.const T_PTR  = 4               // pointer: 16-bit address, descriptor index (kind T_PTR) names the type it points to
.const T_REAL = 5               // real: 4-byte floating point number, in the float accumulator while evaluated
// codes from T_ARRAY on are structured types (their value is an address); everything below is scalar
.const T_ARRAY  = 6             // array: descriptor index in the symbol's field 20 / 'edesc'
.const T_STRING = 7             // string: length byte + characters, descriptor index as for arrays
.const T_RECORD = 8             // record: descriptor index as for arrays; fields are K_FIELD symbols
.const T_BYTE = 3               // 0..255; one byte in global storage, a 16-bit cell in locals

// ---- type descriptor layout (16 bytes each, see types.asm) -------------------------------
.const D_KIND  = 0              // T_ARRAY or T_STRING
.const D_ETYPE = 1              // element type (array) / T_CHAR (string)
.const D_EDESC = 2              // element descriptor index when the element is itself an array/string
.const D_LO    = 4              // lowest index (word); 0 for strings
.const D_HI    = 6              // highest index (word); maximum length for strings
.const D_ESIZE = 8              // size of one element in bytes (word)
.const D_SIZE  = 10             // total size in bytes (word); strings: maximum length + 1

// ---- compile error codes (printed by the harness, see main.asm) --------------------------
.const E_SYNTAX   = 1           // unexpected token / syntax error
.const E_UNDEF    = 2           // undefined identifier
.const E_DUP      = 3           // identifier declared twice
.const E_TYPE     = 4           // type mismatch
.const E_BOOL     = 5           // boolean expression expected
.const E_EOF      = 6           // unexpected end of source (open comment or string)
.const E_MEM      = 7           // out of memory (code, data or symbol table full)
.const E_STR      = 8           // string literal too long
.const E_CHARLIT  = 9           // string used where a single character is required
.const E_ARGS     = 10          // wrong number of arguments / too many parameters

