pub const ConditionFlag = @import("./cond.zig").ConditionFlag;
pub const MappedRegister = @import("./mapped_register.zig").MappedRegister;
pub const Opcode = @import("opcode.zig").Opcode;
pub const Register = @import("register.zig").Register;
pub const Trap = @import("trap.zig").Trap;

/// memory size 2^16 (65536)
pub const MEMORY_MAX = 1 << 16;
