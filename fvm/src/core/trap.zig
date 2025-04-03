pub const Trap = enum(u16) {
    /// get char from keyboard, not echoed onto the terminal
    GETC = 0x20,

    /// print a character
    OUT = 0x21,

    /// print a word string
    PUTS = 0x22,

    /// get char from keyboard, echoed onto the terminal
    IN = 0x23,

    /// output a byte string
    PUTSP = 0x24,

    /// hat the program
    HALT = 0x25,
};
