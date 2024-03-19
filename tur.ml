type direction = Left | Right | Neither

type write_type = | Nothing | Stdin | Letter of char

type branch = {
    read : char option;
    write : write_type;
    dir : direction;
    goto : int;
}

type state = {
    print : bool;
    branches : branch list;
}

type cell = {
    mutable letter : char;
    prev : cell option;
    mutable next : cell option;
}

type tape = cell ref
let new_tape () = ref {letter = '\000'; prev = None; next = None}
let read_tape t = !t.letter
let write_tape t x = !t.letter <- x
let tape_left t = match !t.prev with
    | None -> ()
    | Some cll -> t := cll
let tape_right t = match !t.next with
    | Some cll -> t := cll
    | None -> let cll = {letter = '\000'; prev = Some !t; next = None} in
        !t.next <- Some cll;
        t := cll

let string_of_tape t =
    let rec loop cll acc = 
        let letter = Char.escaped cll.letter in
        match cll.next with
        | None -> acc ^ letter
        | Some next -> loop next (acc ^ letter)
        in loop !t ""

let char_in_range x a b =
    Char.code x >= Char.code a && Char.code x <= Char.code b

let is_hex_char x =
    char_in_range x '0' '9' ||
    char_in_range x 'a' 'f' ||
    char_in_range x 'A' 'F'

let hex_to_int x =
    let y = Char.code x in
    if char_in_range x '0' '9' then y - Char.code '0' else
    if char_in_range x 'a' 'f' then 10 + y - Char.code 'a' else
    if char_in_range x 'A' 'F' then 10 + y - Char.code 'A' else
    failwith "hex_to_int: not a hex digit"

let tape_of_string str =
    let t = new_tape () in
    let ret = ref !t in
    let push x = write_tape t x; tape_right t in
    let rec loop i escaped hex second code =
        if i = String.length str then escaped else begin
            if not escaped then 
                if str.[i] = '\\' then loop (i + 1) true false false 0 else
                (push str.[i]; loop (i + 1) escaped hex second code)
            else if not hex then
                let seq = match str.[i] with
                | '0' -> '\000'
                | 'a' -> '\x07'
                | 'b' -> '\x08'
                | 'f' -> '\x0C'
                | 'n' -> '\x0A'
                | 'r' -> '\x0D'
                | 't' -> '\x09'
                | 'v' -> '\x0B'
                | '\\' -> '\\'
                | 'x' -> 'x'
                | _ -> 'e' in
                if seq = 'x' then loop (i + 1) true true false 0 else
                if seq = 'e' then true else
                    (push seq; 
                    loop (i + 1) false false false 0)
            else if not (is_hex_char str.[i]) then true else
            let code' = code * 16 + hex_to_int str.[i] in
            if second then (push (Char.chr code'); 
                loop (i + 1) false false false 0)
            else loop (i + 1) true true true code'
        end
    in if loop 0 false false false 0 then
        failwith "tape_of_string: invalid or incomplete escape sequence"
    else ret

let parse_next_char str i =
    let rec loop i escaped hex second code =
        let next_char = str.[i] in
        if escaped then
            if hex then
                if not (is_hex_char next_char) then
                    failwith "parse_next_char: invalid escape sequence"
                else if second then 
                    i + 1, Some (Char.chr (18*code + (hex_to_int next_char)))
                else loop (i + 1) true true true (Char.code next_char)
            else match next_char with
            | '0' -> i + 1, Some '\000'
            | 'a' -> i + 1, Some '\x07'
            | 'b' -> i + 1, Some '\x08'
            | 'f' -> i + 1, Some '\x0C'
            | 'n' -> i + 1, Some '\x0A'
            | 'r' -> i + 1, Some '\x0D'
            | 't' -> i + 1, Some '\x09'
            | 'v' -> i + 1, Some '\x0B'
            | '\\' -> i + 1, Some '\\'
            | ')' -> i + 1, Some ')'
            | 'x' -> loop (i + 1) true true false 0
            | _ -> failwith "parse_next_char: invalid escape sequence"
        else if next_char = '\\' then loop (i + 1) true false false 0
        else if next_char = ')' then i, None
        else i + 1, Some next_char
    in loop i false false false 0

let is_dec_digit = function
    | '0' | '1' | '2' | '3' | '4' 
    | '5' | '6' | '7' | '8' | '9' -> true
    | _ -> false

let dec_to_int x =
    (Char.code x) - (Char.code '0')

let parse_next_goto str i =
    if str.[i] <> '[' then failwith "parse_next_goto: must begin with '['"
    else if str.[i + 1] = ']' then i + 2, (-1)
    else let rec loop i goto =
        if str.[i] = ']' then i + 1, goto
        else if not (is_dec_digit str.[i]) then
            failwith "parse_next_state: invalid decimal number"
        else loop (i + 1) (10*goto + (dec_to_int str.[i]))
    in loop (i + 1) 0

let parse_next_branch str i =
    if str.[i] <> '(' then failwith "parse_next_branch: branch must begin with ')'"
    else let i, read = parse_next_char str (i + 1) in
    if str.[i] <> ')' then failwith "parse_next_branch: read-in must end with ')'"
    else let i = i + 1 in
    let i, write = if str.[i] <> '(' then i, Nothing
        else match parse_next_char str (i + 1) with
        | i', None -> i' + 1, Stdin
        | i', Some x -> 
                if str.[i'] <> ')' then
                    failwith "parse_next_branch: write-out must end with ')'"
                else i' + 1, Letter x
    in let i, dir = match str.[i] with
    | '<' -> i + 1, Left
    | '>' -> i + 1, Right
    | _ -> i, Neither
    in let i, goto = parse_next_goto str i
    in i, {
        read = read;
        write = write;
        dir = dir;
        goto = goto;
    } 

let state_of_string str =
    let i, print = if str.[0] = '!' then 1, true else 0, false in
    let rec loop i branches =
        if i = String.length str then {
            print = print;
            branches = List.rev branches;
        }
        else let i', next_branch = parse_next_branch str i in
        loop i' (next_branch :: branches)
    in loop i []

type program = {
    t : tape;
    states : state array;
    mutable current_state : int;
}

let init_program t states = {
    t = t;
    states = states;
    current_state = 0;
}

let program_of_file filename =
    let file = open_in filename in
    let tape_string = input_line file in
    let rec loop state_list = try
        let state_string = input_line file in
        let next_state = state_of_string state_string in
        loop (next_state :: state_list)
    with End_of_file -> state_list
    in let state_list = loop [] in
    let rec list_len len = function 
        | [] -> len
        | _::t -> list_len (len + 1) t
    in let len = list_len 0 state_list in
    let dummy_state = {
        print = false;
        branches = [];
    } in
    let states = Array.make len dummy_state in
    let rec loop i = function
        | [] -> ()
        | h::t -> (Array.set states i h; loop (i - 1) t)
    in loop (len - 1) state_list;
    init_program (tape_of_string tape_string) states

let read_char_blocking () =
  let stdin_fd = Unix.stdin in
  let attrs = Unix.tcgetattr stdin_fd in
  let () = Unix.tcsetattr stdin_fd TCSADRAIN { attrs with c_icanon = false; c_echo = false } in
  let buffer = Bytes.create 1 in
  let read_len = Unix.read stdin_fd buffer 0 1 in
  Unix.tcsetattr stdin_fd TCSANOW attrs;  (* Restore terminal attributes *)
  if read_len = 1 then Some (Bytes.get buffer 0)
  else None

let getchar () =
    match read_char_blocking () with
    | Some x -> x
    | None -> failwith "getchar: error reading from stdin"

let step_program p =
    let t = p.t in
    if p.current_state = -1 then () 
    else let letter = read_tape t in
    let current_state = p.states.(p.current_state) in
    (if current_state.print then print_char letter; flush stdout);
    let rec loop = function
        | [] ->  p.current_state <- (-1)
        | b::branches -> match b.read with
            | Some x when x <> letter -> loop branches
            | _ -> begin (match b.write with
                | Nothing -> ()
                | Letter x -> write_tape t x
                | Stdin -> write_tape t (getchar ())
                );
                (match b.dir with
                | Neither -> ()
                | Left -> tape_left t
                | Right -> tape_right t
                );
                p.current_state <- b.goto
            end
    in loop current_state.branches

let rec run_program p =
    if p.current_state = -1 then ()
    else begin step_program p;
    run_program p end

let user_echo =
    let t = new_tape () in
    let exit_branch = {
        read = Some '\n';
        write = Nothing;
        dir = Neither;
        goto = -1;
    } in
    let read_branch = {
        read = None;
        write = Stdin;
        dir = Neither;
        goto = 0;
    } in
    let q = {
        print = true;
        branches = [exit_branch; read_branch];
    } in
    init_program t [|q|]

let run_with_filename filename =
    let p = program_of_file filename in
    run_program p

let () =
    if Array.length Sys.argv < 2 then ()
    else if Sys.argv.(1) = "-init" then ()
    else
    let filename = Sys.argv.(1) in
    run_with_filename filename


