pub const Register = enum(u16) {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    PC,
    COND,
    COUNT,

    pub fn str(self: Register) []const u8 {
        return switch (self) {
            Register.R0 => "R0",
            Register.R1 => "R1",
            Register.R2 => "R2",
            Register.R3 => "R3",
            Register.R4 => "R4",
            Register.R5 => "R5",
            Register.R6 => "R6",
            Register.R7 => "R7",
            Register.PC => "PC",
            Register.COND => "COND",
            Register.COUNT => "COUNT",
        };
    }
};
