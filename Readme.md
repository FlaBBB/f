# Implementation of LC3 Assembler & VM in Zig


# assembler

had helper like label

## how it works??

example:
simple instruction
```
#start {
    ADD R1 R1 1 // increment
    ADD R1 R1 -1 // decrement
    AND R2 R3 0xff // and, take 1 lower bytes
}
```

label instruction:
```
#add {
    ADD R1 R1 R2 // adding r1 with r2 -> {R1 = R1 + R2}
}

#start {
    LOOP:
    ADD R1 R1 10
    ADD R2 R2 90
    CALL add
    // now R1 is 100;

    JMP LOOP // label
}
```