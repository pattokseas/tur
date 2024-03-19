tur is an interpreted Turing Machine language. It is single-tape and deterministic. Since tur is literally a Turing Machine simulator, it is Turing complete.   
The interpreter is written in OCaml. To run it in the top-level, run
```
#require "unix";;
#use "tur.ml";;
```
Then you can interpret a file with `run_with_filename "my_program.tur";;`
You can also use the compiled interpreter from a Linux command line with `./tur my_program.tur`  
The interpreter was compiled with the command `ocamlbuild -pkg unix tur.native`

tur file format:
- Line 1: tape
- Line 2: state 0
- Line n: state n-2

tape format: literal ascii characters except:
- literal \ must be escaped as \\\\
- literal line feed (ascii x0A) must be escaped as \n
- available C escape sequences: \0 \a \b \f \n \r \t \v \\\\
- can encode arbitrary 8-bit character with hex as \xHH
    - hex code must be exactly two hex digits, e.g. \x0A \x6F

state format:
- lead with ! to print character at tape pointer to stdout
- any number (at least 1) of branches with the format (R)(W)D[S]
    - R and W are characters following the same escape rules as the tape
        - one exception: to read or write a literal ')', must have \\)
    - D is either of the characters < or >
    - S is a number in decimal
    - meaning: if the current tape position has R: write W, move the tape pointer in the D direction, and go to state S
    - (R) can be () to indicate that the branch should be taken unconditionally
    - (W) can be omitted to indicate that nothing should be written
    - (W) can be () to get the character to write from stdin
    - D can be omitted to indicate that the tape should not move
    - (S) can be [] to indicate that the program should terminate
- in executing, the program starts at state 0 and executes the first branch with a matching read condition
- if at any state there is no branch with a matched read condition, the program terminates
- if the program tries to go left of the first tape cell, it doesn't move
- abstractly, there are infinitely many cells to the right
    - all cells are initialized as \0 (except of course the cells given by Line 1)

example: hello world

```
hello, world!\n
(\0)[]()[1]
!()>[0]
```

meaning:
- the tape contains the string to print, "hello, world\n"
- state 0 terminates if the tape is at a null character. otherwise it goes to state 1
- state 1 prints the current character and goes to state 0

example: capitalize
```
\0some text to capitalize and print!\n
()>[1]
(a)(A)>[1](b)(B)>[1](c)(C)>[1](d)(D)>[1](e)(E)>[1](f)(F)>[1](g)(G)>[1](h)(H)>[1](i)(I)>[1](j)(J)>[1](k)(K)>[1](l)(L)>[1](m)(M)>[1](n)(N)>[1](o)(O)>[1](p)(P)>[1](q)(Q)>[1](r)(R)>[1](s)(S)>[1](t)(T)>[1](u)(U)>[1](v)(V)>[1](w)(W)>[1](x)(X)>[1](y)(Y)>[1](z)(Z)>[1](\0)<[2]()>[1]
(\0)>[3]()<[2]
(\0)[]()[4]
!()>[3]
```
meaning:
- the tape contains the text to capitalize, after a null character used to mark the beginning of the tape
- state 0 unconditionally goes to the right and to state 1 without writing anything
- the first 26 branches of state 1 capitalize and go to the right if the tape has a lowercase letter
    - the next branch goes to state 2 if a null character is reached
    - the last branch goes to the right unconditionally
- state 2 goes right and to state 3 if a null character is read and goes left otherwise
- state 3 terminates if a null character is read. otherwise it goes to state 4
- state 4 prints the current tape letter then goes right and to state 3
- a high level explanation: scan the tape, capitalizing lowercase letters. go left back to the start, then go right again printing each letter until the end

example: user echo
```

()()[1]
!(\n)[]()>[0]
```
meaning:
- staae 0 writes from stdin to the tape and goes to state 1
- state 1 prints the current tape cell, then if it was a line break it terminates, and otherwise it goes right and back to state 0
