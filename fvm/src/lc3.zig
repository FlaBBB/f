const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

const core = @import("./../../core/core.zig");
const Register = core.Register;
const ConditionFlag = core.ConditionFlag;
const OP = core.Opcode;
const Trap = core.Trap;
const MappedRegister = core.MappedRegister;
const term = @import("./term.zig");

pub const MEMORY_MAX = core.MEMORY_MAX;

pub fn signExtend(val: u16, comptime bitCount: u16) u16 {
    if ((val >> (bitCount - 1)) & 1 == 1) {
        return val | @as(u16, @truncate(0xFFFF << bitCount));
    }
    return val;
}

pub const LC3 = struct {
    memory: [MEMORY_MAX]u16 = undefined,
    reg: [@intFromEnum(Register.COUNT) + 1]u16 = undefined,
    running: bool = false,
    debug: bool = false,

    pub fn init() LC3 {
        var lc3 = LC3{};
        lc3.setup();
        return lc3;
    }

    pub fn setup(self: *LC3) void {
        // clear registers
        self.reg = [_]u16{0} ** (@intFromEnum(Register.COUNT) + 1);

        // since exactly one condition flag should be set at any given time, set the ZRO flag
        self.reg[@intFromEnum(Register.COND)] = @intFromEnum(ConditionFlag.ZRO);

        // set the PC to starting point
        // for now, 0x3000 is the default
        self.reg[@intFromEnum(Register.PC)] = 0x3000;

        self.running = true;
    }

    pub fn loadRom(self: *LC3, rom: []u16) void {
        std.mem.copyForwards(u16, self.memory[0..rom.len], rom);
    }

    fn getReg(self: *LC3, r: Register) u16 {
        return self.reg[@intFromEnum(r)];
    }

    fn setReg(self: *LC3, r: Register, data: u16) void {
        self.reg[@intFromEnum(r)] = data;
    }

    fn memRead(self: *LC3, address: u16) u16 {
        if (address == @intFromEnum(MappedRegister.KBSR)) {
            if (term.checkKey()) {
                var buf: [1]u8 = undefined;
                _ = std.io.getStdIn().read(&buf) catch {
                    buf[0] = 0;
                    return 0;
                };

                if (self.debug) {
                    std.debug.print("| Inputting '{c}'| ", .{buf[0]});
                }

                self.memory[@intFromEnum(MappedRegister.KBSR)] = (1 << 15);
                self.memory[@intFromEnum(MappedRegister.KBDR)] = @intCast(buf[0]);
            } else {
                self.memory[@intFromEnum(MappedRegister.KBSR)] = 0;
            }
        }
        return self.memory[address];
    }

    fn memWrite(self: *LC3, address: u16, data: u16) void {
        self.memory[address] = data;
    }

    fn getInstr(self: *LC3) u16 {
        const pcV: u16 = self.getReg(Register.PC);
        const instr: u16 = self.memRead(pcV);

        return instr;
    }

    fn incrementPc(self: *LC3) void {
        self.setReg(Register.PC, self.getReg(Register.PC) + 1);
    }

    pub fn virtualize(self: *LC3) void {
        while (self.running) {
            const instr: u16 = self.getInstr();
            const op: OP = @enumFromInt(instr >> 12);

            if (self.debug) {
                std.debug.print("0x{X}: ", .{self.getReg(Register.PC)});
            }

            self.incrementPc();

            switch (op) {
                OP.ADD => self.opAdd(instr),
                OP.AND => self.opAnd(instr),
                OP.NOT => self.opNot(instr),
                OP.BR => self.opBr(instr),
                OP.JMP => self.opJmp(instr),
                OP.JSR => self.opJsr(instr),
                OP.LD => self.opLd(instr),
                OP.LDI => self.opLdi(instr),
                OP.LDR => self.opLdr(instr),
                OP.LEA => self.opLea(instr),
                OP.ST => self.opSt(instr),
                OP.STI => self.opSti(instr),
                OP.STR => self.opStr(instr),
                OP.TRAP => self.opTrap(instr),
                OP.RES, OP.RTI => {
                    @panic("BAD OPCODES");
                },
            }
        }
    }

    fn updateFlags(self: *LC3, r: Register) void {
        const val = self.getReg(r);
        const newFlags: ConditionFlag = switch (val) {
            0 => ConditionFlag.ZRO,
            else => switch (val >> 15) {
                1 => ConditionFlag.NEG,
                else => ConditionFlag.POS,
            },
        };
        self.setReg(Register.COND, @intFromEnum(newFlags));
    }

    fn opAdd(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7); // destination register (DR)
        const r1: Register = @enumFromInt((instr >> 6) & 0x7); // first operand (SR1)
        const immFlag: bool = (instr >> 5) & 0x1 == 1; // immediate flag, whether we use immediate value

        const r1V: u16 = self.getReg(r1);

        if (immFlag) {
            const imm5: u16 = signExtend(instr & 0x1F, 5);

            if (self.debug) {
                std.debug.print("ADD r.{s} r.{s} 0x{X}\n", .{ r0.str(), r1.str(), imm5 });
            }

            const r0V: u16, _ = @addWithOverflow(r1V, imm5);

            self.setReg(r0, r0V);
        } else {
            const r2: Register = @enumFromInt(instr & 0x7);
            const r2V: u16 = self.getReg(r2);

            if (self.debug) {
                std.debug.print("ADD r.{s} r.{s} r.{s}\n", .{ r0.str(), r1.str(), r2.str() }); 
            }

            const r0V, _ = @addWithOverflow(r1V, r2V);

            self.setReg(r0, r0V);
        }

        self.updateFlags(r0);
    }

    fn opAnd(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const r1: Register = @enumFromInt((instr >> 6) & 0x7);
        const immFlag: bool = (instr >> 5) & 0x1 == 1;

        const r1V: u16 = self.getReg(r1);

        if (immFlag) {
            const imm5 = signExtend(instr & 0x1F, 5);

            if (self.debug) {
                std.debug.print("AND r.{s} r.{s} 0x{X}\n", .{ r0.str(), r1.str(), imm5 });
            }

            self.setReg(r0, r1V & imm5);
        } else {
            const r2: Register = @enumFromInt(instr & 0x7);
            const r2V: u16 = self.getReg(r2);

            if (self.debug) {
                std.debug.print("AND r.{s} r.{s} r.{s}\n", .{ r0.str(), r1.str(), r2.str() });
            }

            self.setReg(r0, r1V & r2V);
        }

        self.updateFlags(r0);
    }

    fn opNot(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const r1: Register = @enumFromInt((instr >> 6) & 0x7);

        const r1V: u16 = self.getReg(r1);

        self.setReg(r0, ~r1V);

        if (self.debug) {
            std.debug.print("NOT r.{s} r.{s}\n", .{ r0.str(), r1.str() });
        }

        self.updateFlags(r0);
    }

    fn opBr(self: *LC3, instr: u16) void {
        const n: bool = (instr >> 11) & 0x1 == 1;
        const z: bool = (instr >> 10) & 0x1 == 1;
        const p: bool = (instr >> 9) & 0x1 == 1;
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        const flags: ConditionFlag = @enumFromInt(self.getReg(Register.COND));

        if (self.debug) {
            std.debug.print("BR ", .{});
            if (n) {
                std.debug.print("n", .{});
            } else if (z) {
                std.debug.print("z", .{});
            } else if (p) {
                std.debug.print("p", .{});
            } else {
                std.debug.print("nzp", .{});
            }
            std.debug.print(" 0x{X}\n", .{off9});
        }

        if ((n and flags == ConditionFlag.NEG) or (z and flags == ConditionFlag.ZRO) or (p and flags == ConditionFlag.POS)) {
            var pcV: u16 = self.getReg(Register.PC);
            pcV, _ = @addWithOverflow(pcV, off9);
            self.setReg(Register.PC, pcV);
        }
    }

    fn opJmp(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 6) & 0x7);
        const r0V: u16 = self.getReg(r0);

        if (self.debug) {
            std.debug.print("JMP r.{s}\n", .{r0.str()});
        }

        self.setReg(Register.PC, r0V);
    }

    fn opJsr(self: *LC3, instr: u16) void {
        self.setReg(Register.R7, self.getReg(Register.PC));

        const immFlag: bool = (instr >> 11) & 0x1 == 1;

        if (immFlag) {
            const pcOff11: u16 = signExtend(instr & 0x7FF, 11);
            var pcV: u16 = self.getReg(Register.PC);

            if (self.debug) {
                std.debug.print("JSR #0x{X}\n", .{pcOff11});
            }

            pcV, _ = @addWithOverflow(pcV, pcOff11);

            self.setReg(Register.PC, pcV);
        } else {
            const r0: Register = @enumFromInt((instr >> 6) & 0x7);
            const r0V: u16 = self.getReg(r0);

            if (self.debug) {
                std.debug.print("JSRR r.{s}\n", .{r0.str()});
            }

            self.setReg(Register.PC, r0V);
        }
    }

    fn opLd(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        var pcV: u16 = self.getReg(Register.PC);

        pcV, _ = @addWithOverflow(pcV, off9);

        self.setReg(r0, self.memRead(pcV));

        if (self.debug) {
            std.debug.print("LD r.{s} 0x{X}\n", .{ r0.str(), off9 });
        }

        self.updateFlags(r0);
    }

    fn opLdi(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        var pcV: u16 = self.getReg(Register.PC);

        pcV, _ = @addWithOverflow(pcV, off9);

        self.setReg(r0, self.memRead(self.memRead(pcV)));

        if (self.debug) {
            std.debug.print("LDI r.{s} 0x{X}\n", .{ r0.str(), off9 });
        }

        self.updateFlags(r0);
    }

    fn opLdr(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const r1: Register = @enumFromInt((instr >> 6) & 0x7);
        const off6: u16 = signExtend(instr & 0x3F, 6);

        var r1V: u16 = self.getReg(r1);

        r1V, _ = @addWithOverflow(r1V, off6);

        self.setReg(r0, self.memRead(r1V));

        if (self.debug) {
            std.debug.print("LDR r.{s} r.{s} 0x{X}\n", .{ r0.str(), r1.str(), off6 });
        }

        self.updateFlags(r0);
    }

    fn opLea(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        var pcV: u16 = self.getReg(Register.PC);

        pcV, _ = @addWithOverflow(pcV, off9);

        self.setReg(r0, pcV);

        if (self.debug) {
            std.debug.print("LEA r.{s} 0x{X}\n", .{ r0.str(), off9 });
        }

        self.updateFlags(r0);
    }

    fn opSt(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        var pcV: u16 = self.getReg(Register.PC);

        if (self.debug) {
            std.debug.print("ST r.{s} 0x{X}\n", .{ r0.str(), off9 });
        }

        pcV, _ = @addWithOverflow(pcV, off9);

        self.memWrite(pcV, self.getReg(r0));
    }

    fn opSti(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const off9: u16 = signExtend(instr & 0x1FF, 9);

        var pcV: u16 = self.getReg(Register.PC);

        if (self.debug) {
            std.debug.print("STI r.{s} 0x{X}\n", .{ r0.str(), off9 });
        }

        pcV, _ = @addWithOverflow(pcV, off9);

        self.memWrite(self.memRead(pcV), self.getReg(r0));
    }

    fn opStr(self: *LC3, instr: u16) void {
        const r0: Register = @enumFromInt((instr >> 9) & 0x7);
        const r1: Register = @enumFromInt((instr >> 6) & 0x7);
        const off6: u16 = signExtend(instr & 0x3F, 6);

        var r1V: u16 = self.getReg(r1);

        if (self.debug) {
            std.debug.print("STR r.{s} r.{s} 0x{X}\n", .{ r0.str(), r1.str(), off6 });
        }

        r1V, _ = @addWithOverflow(r1V, off6);

        self.memWrite(r1V, self.getReg(r0));
    }

    fn opTrap(self: *LC3, instr: u16) void {
        self.setReg(Register.R7, self.getReg(Register.PC));

        const trap: Trap = @enumFromInt(instr & 0xFF);

        if (self.debug) {
            std.debug.print("TRAP {}\n", .{trap});
        }

        switch (trap) {
            Trap.GETC => {
                const c: u16 = @intCast(stdin.readByte() catch unreachable);
                self.setReg(Register.R0, c);
                self.updateFlags(Register.R0);
            },
            Trap.OUT => {
                const c: u8 = @truncate(self.getReg(Register.R0));
                stdout.writeByte(c) catch unreachable;
            },
            Trap.PUTS => {
                var address: u16 = self.getReg(Register.R0);
                var c: u8 = @truncate(self.memRead(address));
                while (c != 0) {
                    stdout.writeByte(c) catch unreachable;
                    address += 1;
                    c = @truncate(self.memRead(address));
                }
            },
            Trap.IN => {
                const c: u8 = stdin.readByte() catch unreachable;

                stdout.writeByte(c) catch unreachable;

                self.setReg(Register.R0, @intCast(c));
                self.updateFlags(Register.R0);
            },
            Trap.PUTSP => {
                var address: u16 = self.getReg(Register.R0);
                var mem: u16 = self.memRead(address);
                while (mem != 0) {
                    const c1: u8 = @truncate(mem);
                    stdout.writeByte(c1) catch unreachable;

                    const c2: u8 = @truncate(mem >> 8);
                    if (c2 != 0) {
                        stdout.writeByte(c2) catch unreachable;
                    }

                    address += 1;
                    mem = self.memRead(address);
                }
            },
            Trap.HALT => {
                self.running = false;
            },
        }
    }
};
