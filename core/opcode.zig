/// list of opcodes that used in lc3 architecture \
/// check detail on https://acg.cis.upenn.edu/milom/cse240-Fall05/handouts/Ch05.pdf
pub const Opcode = enum(u16) {
    /// operator branch
    BR,

    /// operator add
    ADD,

    /// operator load
    LD,

    /// operator store
    ST,

    /// operator jump register
    JSR,

    /// operator bitwise and
    AND,

    /// operator load register
    LDR,

    /// operator store register
    STR,

    /// unused operator
    RTI,

    /// operator bitwise not
    NOT,

    /// operator load indirect
    LDI,

    /// operator store indirect
    STI,

    /// operator jump
    JMP,

    /// reserved (unused) operator
    RES,

    /// operator load effective address
    LEA,

    /// operator execution trap
    TRAP,

    pub fn str(self: Opcode) []const u8 {
        return switch (self) {
            Opcode.BR => "BR",
            Opcode.ADD => "ADD",
            Opcode.LD => "LD",
            Opcode.ST => "ST",
            Opcode.JSR => "JSR",
            Opcode.AND => "AND",
            Opcode.LDR => "LDR",
            Opcode.STR => "STR",
            Opcode.RTI => "RTI",
            Opcode.NOT => "NOT",
            Opcode.LDI => "LDI",
            Opcode.STI => "STI",
            Opcode.JMP => "JMP",
            Opcode.RES => "RES",
            Opcode.LEA => "LEA",
            Opcode.TRAP => "TRAP",
        };
    }
};
