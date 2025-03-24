const std = @import("std");

const core = @import("./../../core/core.zig");
const OP = core.Opcode;
const Register = core.Register;
const Trap = core.Trap;

/// A dynamically resizable string implementation.
///
/// This struct provides a way to manage a string buffer with dynamic resizing
/// capabilities. It uses an allocator to manage memory and provides methods
/// for initialization, resizing, appending, and freeing the buffer.
///
/// Fields:
/// - `allocator`: The memory allocator used for managing the buffer.
/// - `buff`: The underlying buffer storing the string data.
/// - `ptr`: The current position in the buffer (i.e., the length of the string).
///
/// Methods:
/// - `init`: Initializes a `String` with a specified buffer size.
/// - `initFast`: Initializes a `String` with a default buffer size of 4096 bytes.
/// - `resize`: Resizes the buffer to a specified size.
/// - `resizeFast`: Doubles the size of the buffer.
/// - `leftSize`: Returns the remaining space in the buffer.
/// - `append`: Appends a single byte to the string, resizing the buffer if necessary.
/// - `free`: Frees the memory allocated for the buffer.
pub const String = struct {
    allocator: std.mem.Allocator,
    buff: []u8,
    ptr: usize,

    pub fn init(allocator: std.mem.Allocator, size: usize) !String {
        return .{
            .allocator = allocator,
            .buff = try allocator.alloc(u8, size),
            .ptr = 0,
        };
    }

    pub fn initFast(allocator: std.mem.Allocator) !String {
        return try String.init(allocator, 4096);
    }

    pub fn resize(self: *String, size: usize) !void {
        self.buff = try self.allocator.realloc(self.buff, size);
    }

    pub fn resizeFast(self: *String) !void {
        try self.resize(self.buff.len * 2);
    }

    pub fn leftSize(self: *String) usize {
        return self.buff.len - self.ptr;
    }

    pub fn append(self: *String, byte: u8) !void {
        if (self.leftSize() < 1) {
            try self.resizeFast();
        }

        self.buff[self.ptr] = byte;
        self.ptr += 1;
    }

    pub fn free(self: *String) void {
        self.allocator.free(self.buff);
    }
};

/// Represents the operands used in an instruction.
/// This includes destination and source registers, flags, and immediate values.
pub const Operands = struct {
    /// Destination register.
    dr: Register = undefined,

    /// Source register 1 (SR1) or BaseR.
    sr1: Register = undefined,

    /// Source register 2 (SR2).
    sr2: Register = undefined,

    /// Flag 1 or (n) in BR.
    flag1: bool = undefined,

    /// Flag 2 (p) in BR.
    flag2: bool = undefined,

    /// Flag 3 (z) in BR.
    flag3: bool = undefined,

    /// Immediate value, used in imm5 / offset.
    imm: u16 = undefined,
};

/// Metadata associated with an instruction.
/// This includes offsets, pointers to other instructions, and additional helper data.
pub const Metadata = struct {
    /// Used in JMP/CALL(JSR) instructions, representing abstract code like {JMP LABEL} or {CALL(JSR) LABEL_SUB}.
    jmpLabel: Label = undefined,

    /// Used in LEA instructions, representing abstract code like {LEA REG "Hello World"}.
    localData: TypedFragment(.Data) = undefined,

    /// Used in LEA instructions, representing abstract code like {LEA REG .HelloWorld}.
    globalData: GlobalStaticData = undefined,
};

/// Represents a single instruction in the program.
/// Contains the opcode, operands, and associated metadata.
pub const Instruction = struct {
    /// Opcode of the instruction.
    op: OP,

    /// Operands used by the instruction.
    opr: Operands,

    /// Metadata providing additional context for the instruction.
    meta: Metadata = .{},
};

pub const LocalStaticData = struct {
    /// represent data
    data: type,
};

pub const GlobalStaticData = struct {
    /// use this if data is global static data
    address: u16 = undefined,

    /// represent data
    data: type = undefined,
};

pub const FragmentType = enum(usize) {
    Instruction,
    Data,
};

/// Fragment can be either LocalStaticData or Instruction
pub const Fragment = struct {
    /// Offset the instruction depends on, varies by function.
    offset: u16 = undefined,

    fragmentType: FragmentType,

    instruction: Instruction = undefined,
    localData: LocalStaticData = undefined,

    /// Pointer to the next fragment.
    nextFragment: Fragment = undefined,

    /// size of fragment
    size: usize,
};

pub fn TypedFragment(comptime fragmentType: FragmentType) type {
    return struct {
        fragment: *Fragment,

        const Self = @This();

        /// Create a typed fragment view, returns null if types don't match
        pub fn init(fragment: *Fragment) ?Self {
            if (fragment.fragmentType != fragmentType) {
                return null;
            }
            return Self{ .fragment = fragment };
        }

        /// Get the underlying fragment
        pub fn getFragment(self: Self) *Fragment {
            return self.fragment;
        }
    };
}

pub const InstructionFactory = struct {
    pub fn add1(dr: Register, sr1: Register, sr2: Register) Instruction {
        return Instruction{
            .op = .ADD,
            .opr = .{
                .dr = dr,
                .sr1 = sr1,
                .sr2 = sr2,
            },
        };
    }

    pub fn add2(dr: Register, sr1: Register, imm5: u16) Instruction {
        return Instruction{
            .op = .ADD,
            .opr = .{
                .dr = dr,
                .sr1 = sr1,
                .flag1 = true,
                .imm = imm5,
            },
        };
    }

    pub fn and1(dr: Register, sr1: Register, sr2: Register) Instruction {
        return Instruction{
            .op = .AND,
            .opr = .{
                .dr = dr,
                .sr1 = sr1,
                .sr2 = sr2,
            },
        };
    }

    pub fn and2(dr: Register, sr1: Register, imm5: u16) Instruction {
        return Instruction{
            .op = .AND,
            .opr = .{
                .dr = dr,
                .sr1 = sr1,
                .flag1 = true,
                .imm = imm5,
            },
        };
    }

    pub fn br(n: bool, z: bool, p: bool, label: Label) Instruction {
        return Instruction{
            .op = .BR,
            .meta = .{
                .jmpLabel = label,
            },
            .opr = .{
                .flag1 = n,
                .flag2 = z,
                .flag3 = p,
            },
        };
    }

    pub fn jmp(label: Label) Instruction {
        return Instruction{
            .op = .JMP,
            .meta = .{
                .jmpLabel = label,
            },
        };
    }

    pub fn ret() Instruction {
        return Instruction{
            .op = .JMP,
            .opr = .{
                .sr1 = .R7,
            },
        };
    }

    pub fn jsr1(off11: u16) Instruction {
        return Instruction{
            .op = .JSR,
            .opr = .{
                .imm = off11,
            },
        };
    }

    pub fn jsr2(baseR: Register) Instruction {
        return Instruction{
            .op = .JSR,
            .opr = .{
                .sr1 = baseR,
            },
        };
    }

    pub fn ld(dr: Register, off9: u16) Instruction {
        return Instruction{
            .op = .LD,
            .opr = .{
                .dr = dr,
                .imm = off9,
            },
        };
    }

    pub fn ldi(dr: Register, off9: u16) Instruction {
        return Instruction{
            .op = .LDI,
            .opr = .{
                .dr = dr,
                .imm = off9,
            },
        };
    }

    pub fn ldr(dr: Register, baseR: Register, off6: u16) Instruction {
        return Instruction{
            .op = .LDR,
            .opr = .{
                .dr = dr,
                .sr1 = baseR,
                .imm = off6,
            },
        };
    }

    pub fn lea(dr: Register, off9: u16) Instruction {
        return Instruction{
            .op = .LEA,
            .opr = .{
                .dr = dr,
                .imm = off9,
            },
        };
    }

    pub fn leaData(dr: Register, data: LocalStaticData) Instruction {
        return Instruction{
            .op = .LEA,
            .opr = .{
                .dr = dr,
            },
            .meta = .{
                .localData = data,
            },
        };
    }

    pub fn not(dr: Register, sr: Register) Instruction {
        return Instruction{
            .op = .NOT,
            .opr = .{
                .dr = dr,
                .sr1 = sr,
            },
        };
    }

    pub fn st(sr: Register, off9: u16) Instruction {
        return Instruction{
            .op = .ST,
            .opr = .{
                .sr1 = sr,
                .imm = off9,
            },
        };
    }

    pub fn sti(sr: Register, off9: u16) Instruction {
        return Instruction{
            .op = .STI,
            .opr = .{
                .sr1 = sr,
                .imm = off9,
            },
        };
    }

    pub fn str(sr: Register, baseR: Register, off6: u16) Instruction {
        return Instruction{
            .op = .STR,
            .opr = .{
                .sr1 = sr,
                .sr2 = baseR,
                .imm = off6,
            },
        };
    }

    pub fn trap(trap8: Trap) Instruction {
        return Instruction{
            .op = .TRAP,
            .opr = .{
                .imm = @intFromEnum(trap8),
            },
        };
    }
};

/// Represents a label in the program.
/// Labels are used for jump instructions and define specific points in the code.
pub const Label = struct {
    /// Name of the label.
    name: String,

    /// List of instructions that may jump to this label, used to define the jump address.
    dependInsts: std.ArrayList(Instruction),

    /// Starting point instruction associated with this label.
    inst: Instruction = undefined,
};

/// Represents a function in the program.
/// Functions consist of a base address, a primary label, and additional labels.
pub const Function = struct {
    /// Primary label for the function.
    label: Label,

    /// Base address of the function.
    baseAddress: u16 = undefined,

    /// Additional labels within the function.
    labels: std.ArrayList(Label),

    headFrag: Fragment = undefined,

    tailFrag: Fragment = undefined,

    pub fn addFragment(self: *Function, frag: Fragment) void {
        if (self.headFrag == undefined) {
            frag.offset = 0;

            self.headFrag = frag;
            self.tailFrag = frag;
            return;
        }

        if (self.tailFrag == undefined) {
            self.tailFrag = self.headFrag;
        }

        while (self.tailFrag.nextFragment != undefined) {
            self.tailFrag = self.tailFrag.nextFragment;
        }

        frag.offset = self.tailFrag.offset + self.tailFrag.size;

        self.tailFrag.nextFragment = frag;
        self.tailFrag = frag;
    }

    pub fn addInstruction(self: *Function, inst: Instruction) Fragment {
        const fragment: Fragment = .{
            .fragmentType = .Instruction,
            .instruction = inst,
            .size = 1,
        };

        self.addFragment(fragment);
        return fragment;
    }

    pub fn addData(self: *Function, data: type, size: usize) Fragment {
        const fragment: Fragment = .{
            .fragmentType = .Data,
            .localData = .{
                .data = data,
            },
            .size = size,
        };

        self.addFragment(fragment);
        return fragment;
    }
};
