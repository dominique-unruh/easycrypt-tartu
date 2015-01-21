(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

{
  open EcUtils
  open EcParser

  module L = EcLocation

  exception LexicalError of L.t option * string

  let lex_error lexbuf msg =
    raise (LexicalError (Some (L.of_lexbuf lexbuf), msg))

  let unterminated_comment () =
    raise (LexicalError (None, "unterminated comment"))

  let unterminated_string () =
    raise (LexicalError (None, "unterminated string"))

  let _keywords = [                     (* see [keywords.py] *)
    "admit"       , ADMIT      ;        (* KW: dangerous *)

    "forall"      , FORALL     ;        (* KW: prog *)
    "exists"      , EXIST      ;        (* KW: prog *)
    "fun"         , FUN        ;        (* KW: prog *)
    "glob"        , GLOB       ;        (* KW: prog *)
    "let"         , LET        ;        (* KW: prog *)
    "in"          , IN         ;        (* KW: prog *)
    "var"         , VAR        ;        (* KW: prog *)
    "proc"        , PROC       ;        (* KW: prog *)
    "if"          , IF         ;        (* KW: prog *)
    "then"        , THEN       ;        (* KW: prog *)
    "else"        , ELSE       ;        (* KW: prog *)
    "elif"        , ELIF       ;        (* KW: prog *)
    "while"       , WHILE      ;        (* KW: prog *)
    "assert"      , ASSERT     ;        (* KW: prog *)
    "return"      , RETURN     ;        (* KW: prog *)
    "res"         , RES        ;        (* KW: prog *)
    "equiv"       , EQUIV      ;        (* KW: prog *)
    "hoare"       , HOARE      ;        (* KW: prog *)
    "phoare"      , PHOARE     ;        (* KW: prog *)
    "islossless"  , LOSSLESS   ;        (* KW: prog *)

    "try"         , TRY        ;        (* KW: tactical *)
    "first"       , FIRST      ;        (* KW: tactical *)
    "last"        , LAST       ;        (* KW: tactical *)
    "do"          , DO         ;        (* KW: tactical *)
    "strict"      , STRICT     ;        (* KW: tactical *)
    "expect"      , EXPECT     ;        (* KW: tactical *)

    (* Lambda tactics *)
    "beta"        , BETA       ;        (* KW: tactic *)
    "iota"        , IOTA       ;        (* KW: tactic *)
    "zeta"        , ZETA       ;        (* KW: tactic *)
    "logic"       , LOGIC      ;        (* KW: tactic *)
    "delta"       , DELTA      ;        (* KW: tactic *)
    "simplify"    , SIMPLIFY   ;        (* KW: tactic *)
    "congr"       , CONGR      ;        (* KW: tactic *)

    (* Logic tactics *)
    "change"      , CHANGE     ;        (* KW: tactic *)
    "split"       , SPLIT      ;        (* KW: tactic *)
    "left"        , LEFT       ;        (* KW: tactic *)
    "right"       , RIGHT      ;        (* KW: tactic *)
    "generalize"  , GENERALIZE ;        (* KW: tactic *)
    "case"        , CASE       ;        (* KW: tactic *)

    "intros"      , INTROS     ;        (* KW: tactic *)
    "pose"        , POSE       ;        (* KW: tactic *)
    "cut"         , CUT        ;        (* KW: tactic *)
    "elim"        , ELIM       ;        (* KW: tactic *)
    "clear"       , CLEAR      ;        (* KW: tactic *)

    (* Auto tactics *)
    "apply"       , APPLY      ;        (* KW: tactic *)
    "rewrite"     , REWRITE    ;        (* KW: tactic *)
    "rwnormal"    , RWNORMAL   ;        (* KW: tactic *)
    "subst"       , SUBST      ;        (* KW: tactic *)
    "progress"    , PROGRESS   ;        (* KW: tactic *)
    "trivial"     , TRIVIAL    ;        (* KW: tactic *)
    "auto"        , AUTO       ;        (* KW: tactic *)

    (* Other tactics *)
    "idtac"       , IDTAC      ;        (* KW: tactic *)
    "move"        , MOVE       ;        (* KW: tactic *)
    "modpath"     , MODPATH    ;        (* KW: tactic *)
    "fieldeq"     , FIELD      ;        (* KW: tactic *)
    "ringeq"      , RING       ;        (* KW: tactic *)
    "algebra"     , ALGNORM    ;        (* KW: tactic *)

    "exact"       , EXACT      ;        (* KW: bytac *)
    "assumption"  , ASSUMPTION ;        (* KW: bytac *)
    "smt"         , SMT        ;        (* KW: bytac *)
    "by"          , BY         ;        (* KW: bytac *)
    "reflexivity" , REFLEX     ;        (* KW: bytac *)
    "done"        , DONE       ;        (* KW: bytac *)

    (* PHL: tactics *)
    "transitivity", TRANSITIVITY;       (* KW: tactic *)
    "symmetry"    , SYMMETRY   ;        (* KW: tactic *)
    "seq"         , SEQ        ;        (* KW: tactic *)
    "wp"          , WP         ;        (* KW: tactic *)
    "sp"          , SP         ;        (* KW: tactic *)
    "sim"         , SIM        ;        (* KW: tactic *)
    "skip"        , SKIP       ;        (* KW: tactic *)
    "call"        , CALL       ;        (* KW: tactic *)
    "rcondt"      , RCONDT     ;        (* KW: tactic *)
    "rcondf"      , RCONDF     ;        (* KW: tactic *)
    "swap"        , SWAP       ;        (* KW: tactic *)
    "cfold"       , CFOLD      ;        (* KW: tactic *)
    "rnd"         , RND        ;        (* KW: tactic *)
    "pr_bounded"  , PRBOUNDED  ;        (* KW: tactic *)
    "bypr"        , BYPR       ;        (* KW: tactic *)
    "byphoare"    , BYPHOARE   ;        (* KW: tactic *)
    "byequiv"     , BYEQUIV    ;        (* KW: tactic *)
    "fel"         , FEL        ;        (* KW: tactic *)

    "conseq"      , CONSEQ     ;        (* KW: tactic *)
    "exfalso"     , EXFALSO    ;        (* KW: tactic *)
    "inline"      , INLINE     ;        (* KW: tactic *)
    "alias"       , ALIAS      ;        (* KW: tactic *)
    "fission"     , FISSION    ;        (* KW: tactic *)
    "fusion"      , FUSION     ;        (* KW: tactic *)
    "unroll"      , UNROLL     ;        (* KW: tactic *)
    "splitwhile"  , SPLITWHILE ;        (* KW: tactic *)
    "kill"        , KILL       ;        (* KW: tactic *)
    "eager"       , EAGER      ;        (* KW: tactic *)

    "axiom"       , AXIOM      ;        (* KW: global *)
    "hypothesis"  , HYPOTHESIS ;        (* KW: global *)
    "axiomatized" , AXIOMATIZED;        (* KW: global *)
    "lemma"       , LEMMA      ;        (* KW: global *)
    "realize"     , REALIZE    ;        (* KW: global *)
    "choice"      , CHOICE     ;        (* KW: global *)
    "proof"       , PROOF      ;        (* KW: global *)
    "qed"         , QED        ;        (* KW: global *)
    "goal"        , GOAL       ;        (* KW: global *)
    "end"         , END        ;        (* KW: global *)
    "import"      , IMPORT     ;        (* KW: global *)
    "export"      , EXPORT     ;        (* KW: global *)
    "local"       , LOCAL      ;        (* KW: global *)
    "declare"     , DECLARE    ;        (* KW: global *)
    "hint"        , HINT       ;        (* KW: global *)
    "nosmt"       , NOSMT      ;        (* KW: global *)
    "module"      , MODULE     ;        (* KW: global *)
    "of"          , OF         ;        (* KW: global *)
    "const"       , CONST      ;        (* KW: global *)
    "op"          , OP         ;        (* KW: global *)
    "pred"        , PRED       ;        (* KW: global *)
    "require"     , REQUIRE    ;        (* KW: global *)
    "theory"      , THEORY     ;        (* KW: global *)
    "abstract"    , ABSTRACT   ;        (* KW: global *)
    "section"     , SECTION    ;        (* KW: global *)
    "extraction"  , EXTRACTION ;
    "type"        , TYPE       ;        (* KW: global *)
    "class"       , CLASS      ;        (* KW: global *)
    "instance"    , INSTANCE   ;        (* KW: global *)
    "print"       , PRINT      ;        (* KW: global *)
    "search"      , SEARCH     ;        (* KW: global *)
    "why3"        , WHY3       ;        (* KW: global *)
    "as"          , AS         ;        (* KW: global *)
    "Pr"          , PR         ;        (* KW: global *)
    "clone"       , CLONE      ;        (* KW: global *)
    "with"        , WITH       ;        (* KW: global *)
    "prover"      , PROVER     ;        (* KW: global *)
    "timeout"     , TIMEOUT    ;        (* KW: global *)
    "nolocals"    , NOLOCALS   ;        (* KW: global *)

    "undo"        , UNDO       ;        (* KW: internal *)
    "debug"       , DEBUG      ;        (* KW: internal *)
    "pragma"      , PRAGMA     ;        (* KW: internal *)

    "Top"         , TOP        ;        (* KW: global *)
    "Self"        , SELF       ;        (* KW: global *)
  ]

  let keywords = Hashtbl.create 97

  let _ =
    List.iter
      (fun (x, y) -> Hashtbl.add keywords x y)
      _keywords

  exception InvalidCodePosition

  let cposition_of_string =
    let cpos1 x =
      try  int_of_string x
      with Failure "int_of_string" -> raise InvalidCodePosition
    in

    let rec doit = function
      | Str.Text c :: []                  -> (cpos1 c, None)
      | Str.Text c :: Str.Delim "." :: tl -> (cpos1 c, Some (0, doit tl))
      | Str.Text c :: Str.Delim "?" :: tl -> (cpos1 c, Some (1, doit tl))
      | _ -> raise InvalidCodePosition
    in
      fun s -> doit (Str.full_split (Str.regexp "[.?]") s)

  let cposition_of_string s =
    try  Some (cposition_of_string s)
    with InvalidCodePosition -> None
}

let empty   = ""
let blank   = [' ' '\t' '\r']
let newline = '\n'
let upper   = ['A'-'Z']
let lower   = ['a'-'z']
let letter  = upper | lower
let digit   = ['0'-'9']
let uint    = digit+

let ichar  = (letter | digit | '_' | '\'')
let lident = (lower ichar*) | ('_' ichar+)
let uident = upper ichar*
let tident = '\'' lident
let mident = '&'  (lident | uint)

let op_char_1     = ['=' '<' '>']
let op_char_2     = ['+' '-']
let op_char_3_r   = ['*' '%' '\\']
let op_char_3     = op_char_3_r | '/'
let op_char_4_r   = ['$' '&' '^' '|' '#']
let op_char_4     = op_char_4_r | '@'
let op_char_34    = op_char_3 | op_char_4
let op_char_234   = op_char_2 | op_char_34
let op_char_1234  = op_char_1 | op_char_234
let op_char_34_r  = op_char_4_r | op_char_3_r
let op_char_234_r = op_char_2   | op_char_34_r

let op1 = op_char_1234* op_char_1 op_char_1234*
let op2 = op_char_2 | op_char_2 op_char_234_r op_char_234*
let op3 = op_char_34* op_char_3 op_char_34*
let op4 = (op_char_4 op_char_4_r*) | ("::" ':'+)
let nop = '\\' ichar+

let uniop = '!' | op2 | nop
let binop = op1 | op2 | op3 | op4 | nop

(* -------------------------------------------------------------------- *)
rule main = parse
  | newline      { Lexing.new_line lexbuf; main lexbuf }
  | blank+       { main lexbuf }
  | lident as id { try [Hashtbl.find keywords id] with Not_found -> [LIDENT id] }
  | uident as id { try [Hashtbl.find keywords id] with Not_found -> [UIDENT id] }
  | tident       { [TIDENT (Lexing.lexeme lexbuf)] }
  | mident       { [MIDENT (Lexing.lexeme lexbuf)] }
  | uint         { [UINT (int_of_string (Lexing.lexeme lexbuf))] }
  | "<<"         { [BACKS] }
  | ">>"         { [FWDS] }

  | "(*" binop "*)" { main lexbuf }
  | '(' blank* (binop as s) blank* ')' { [PBINOP s] }
  | '[' blank* (uniop as s) blank* ']' { [PUNIOP (Printf.sprintf "[%s]" s)] }

  | "(*" { comment lexbuf; main lexbuf }
  | "\"" { [STRING (Buffer.contents (string (Buffer.create 0) lexbuf))] }

  (* boolean operators *)
  | '!'   { [NOT ] }
  | "&&"  { [ANDA] }
  | "/\\" { [AND ] }
  | "||"  { [ORA ] }
  | "\\/" { [OR  ] }
  | "=>"  { [IMPL] }
  | "<=>" { [IFF ] }

  (* string symbols *)
  | "<-"    { [LARROW   ] }
  | "->"    { [RARROW   ] }
  | "<<-"   { [LLARROW  ] }
  | "->>"   { [RRARROW  ] }
  | ".."    { [DOTDOT   ] }
  | ".["    { [DLBRACKET] }
  | ".`"    { [DOTTICK  ] }
  | ":="    { [CEQ      ] }
  | "::"    { [DCOLON   ] }
  | "%r"    { [FROM_INT ] }
  | "{0,1}" { [RBOOL    ] }

  (* position *)
  | (digit+ ['.' '?'])+ digit+ {
      [CPOS (oget (cposition_of_string (Lexing.lexeme lexbuf)))]
    }

  (* punctuation *)
  | '_'   { [UNDERSCORE] }
  | '('   { [LPAREN    ] }
  | ')'   { [RPAREN    ] }
  | '{'   { [LBRACE    ] }
  | '}'   { [RBRACE    ] }
  | '['   { [LBRACKET  ] }
  | ']'   { [RBRACKET  ] }
  | "<:"  { [LTCOLON   ] }
  | ','   { [COMMA     ] }
  | ';'   { [SEMICOLON ] }
  | ':'   { [COLON     ] }
  | '?'   { [QUESTION  ] }
  | '%'   { [PCENT     ] }
  | "*"   { [STAR      ] }
  | "/"   { [SLASH     ] }
  | "$"   { [SAMPLE    ] }
  | "|"   { [PIPE      ] }
  | "`|"  { [TICKPIPE  ] }
  | "@"   { [AT        ] }
  | "~"   { [TILD      ] }
  | "{|"  { [LPBRACE   ] }
  | "|}"  { [RPBRACE   ] }
  | "==>" { [LONGARROW ] }

  (* equality / ordering *)
  | "="   { [EQ] }
  | "<>"  { [NE] }
  | ">"   { [GT] }
  | "<"   { [LT] }
  | ">="  { [GE] }
  | "<="  { [LE] }

  | "-"   { [MINUS] }
  | "+"   { [ADD  ] }

  | "//"  { [SLASHSLASH  ] }
  | "/="  { [SLASHEQ     ] }
  | "//=" { [SLASHSLASHEQ] }

  | nop as s  { [NOP s] }
  | op1 as s  { [OP1 s] }
  | op2 as s  { [OP2 s] }
  | op3 as s  { [OP3 s] }
  | op4 as s  { [OP4 s] }

  (* end of sentence / stream *)
  | '.' (eof | blank | newline as r) {
      if r = "\n" then
        Lexing.new_line lexbuf;
      [FINAL]
    }

  | "." { [DOT] }

  | eof { [EOF] }

  |  _ as c  { lex_error lexbuf ("illegal character: " ^ String.make 1 c) }

and comment = parse
  | "*)"        { () }
  | "(*"        { comment lexbuf; comment lexbuf }
  | newline     { Lexing.new_line lexbuf; comment lexbuf }
  | eof         { unterminated_comment () }
  | _           { comment lexbuf }

and string buf = parse
  | "\""          { buf }
  | "\\n"         { Buffer.add_char buf '\n'; string buf lexbuf }
  | "\\r"         { Buffer.add_char buf '\r'; string buf lexbuf }
  | "\\" (_ as c) { Buffer.add_char buf c   ; string buf lexbuf }
  | newline       { Buffer.add_string buf (Lexing.lexeme lexbuf); string buf lexbuf }
  | _ as c        { Buffer.add_char buf c   ; string buf lexbuf }
  | eof           { unterminated_string () }
