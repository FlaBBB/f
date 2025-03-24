const std = @import("std");

const core = @import("./../../core/core.zig");
const Register = core.Register;

const types = @import("./types.zig");

const String = types.String;

const Operands = types.Operands;
const Label = types.Label;
const Metadata = types.Metadata;
const Instruction = types.Instruction;
const Function = types.Function;
const LocalStaticData = types.LocalStaticData;
const GlobalStaticData = types.GlobalStaticData;

const InstructionFactory = types.InstructionFactory;

const parserErr = @import("./parser_err.zig");
const ParserError = parserErr.ParserError;

pub fn signToUnsign(val: i16, comptime bitCount: u16) ParserError!u16 {
    if (val >= 0) {
        if (val >= 1 << (bitCount - 1)) {
            return ParserError.IntegerOverflow;
        }

        return @intCast(val);
    }
    if (@abs(val) > 1 << (bitCount - 1)) {
        return ParserError.IntegerOverflow;
    }

    return @intCast((1 << bitCount) + val);
}

pub fn checkOctal(c: u8) bool {
    return switch (c) {
        '0'...'7' => true,
        else => false,
    };
}

pub fn checkBiner(c: u8) bool {
    return switch (c) {
        '0', '1' => true,
        else => false,
    };
}

pub fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t';
}

pub const Parser = struct {
    allocator: std.mem.Allocator,
    reader: std.fs.File.Reader,

    functions: std.AutoHashMap([]const u8, Function),
    staticData: std.AutoHashMap([]const u8, Function),

    token: String,

    line: String,
    lineEnd: bool = false,
    numLine: u64 = 1,

    tempBufer: String,

    isInsideFunction: bool = false,

    pub fn init(fileName: []const u8, allocator: std.mem.Allocator) !Parser {
        const file = try std.fs.cwd().openFile(fileName, .{});

        return .{
            .allocator = allocator,
            .reader = file.reader(),
            .functions = std.ArrayList([]Function).init(allocator),
            .staticDatas = std.ArrayList([]GlobalStaticData).init(allocator),
            .missingFunctions = std.AutoHashMap([]const u8, Function).init(allocator),
            .token = try String.init(allocator, 64),
            .line = try String.initFast(allocator),
            .tempBufer = try String.initFast(allocator),
        };
    }

    fn cleanup(self: *Parser) void {
        // free all allocated string
        self.token.free();
        self.line.free();
        self.tempBufer.free();
    }

    pub fn parse(self: *Parser) void {
        while (true) {
            const byte = self.getbyte() catch return;

            _ = switch (byte) {
                '\\' => self.handleComment(),
                ' ', '\t' => void,
                '#' => self.parseFunction(),
                '.' => self.parseGlobalData(),
            } catch |err| {
                switch (err) {
                    error.EndOFStream => {
                        // TODO: handler errors EndOfStream
                    },
                    ParserError.InvalidSyntax => {
                        // TODO: handler errors InvalidSyntax
                    },
                }
            };
        }
    }

    fn parseFunction(self: *Parser) !void {
        var definitionParsed = false;

        const functionName = try String.init(self.allocator, 64);
        var nameParsed = false;
        var isStart = false;

        const function: Function = Function{
            .label = .{
                .name = functionName,
                .dependInsts = std.ArrayList(Instruction).init(self.allocator),
            },
            .labels = std.ArrayList(Label).init(self.allocator),
        };

        while (true) {
            const byte = try self.getbyte();

            switch (byte) {
                '\\' => self.handleComment(),
                else => {
                    if (!definitionParsed) {
                        if (!nameParsed) {
                            // allow whitespace between function sytax (#) and function name
                            if (functionName.ptr == 0 and (byte == ' ' or byte == '\t')) {
                                continue;
                            }

                            if (byte == ' ' or byte == '\t') {
                                nameParsed = true;
                                continue;
                            }

                            // only allow alphanum
                            if (!std.ascii.isAlphanumeric(byte)) {
                                return ParserError.InvalidSyntax;
                            }

                            // only allow first char is alphabet
                            if (functionName.ptr == 0 and !std.ascii.isAlphabetic(byte)) {
                                return ParserError.InvalidSyntax;
                            }

                            functionName.append(byte);
                            continue;
                        }

                        if (byte == ' ' or byte == '\t') {
                            continue;
                        }

                        if (byte != '{') {
                            return ParserError.InvalidSyntax;
                        }

                        if (std.mem.eql(u8, functionName.buff[0..functionName.ptr], "start")) {
                            isStart = true;

                            // initalize register
                            function.addInstruction(InstructionFactory.lea(.R6, try signToUnsign(-1, 9)));
                        } else {
                            // add stack
                            function.addInstruction(InstructionFactory.add2(.R6, .R6, try signToUnsign(-1, 5)));
                            // store return register if calling this function
                            function.addInstruction(InstructionFactory.str(.R7, .R6, 0));
                        }

                        definitionParsed = true;
                        self.readUntilNewline(); // ignore rest of line if "{" is appear
                        continue;
                    }

                    // start parsing instruction
                    if (self.token.ptr == 0 and (byte == ' ' or byte == '\t')) {
                        continue;
                    }

                    if (byte == ' ' or byte == '\t') {
                        if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "ADD")) {
                            self.token.ptr = 0;

                            var dr: Register = undefined;
                            var sr1: Register = undefined;

                            while (true) {
                                const byte1: u8 = try self.getbyte();

                                if (isWhitespace(byte1)) {
                                    continue;
                                }

                                if (dr == undefined) {
                                    dr = try self.parseAndExtractRegister(byte); // destination register
                                    continue;
                                } else if (sr1 == undefined) {
                                    sr1 = try self.parseAndExtractRegister(byte); // source register 2
                                    continue;
                                }

                                switch (byte1) {
                                    'R' => {
                                        const sr2 = try self.parseAndExtractRegister(byte); // source register 2

                                        function.addInstruction(InstructionFactory.add1(dr, sr1, sr2));
                                    },
                                    '-', '0'...'9' => {
                                        const parsedInt = try self.parseAndExtractInteger(byte);
                                        const imm5: u16 = try signToUnsign(parsedInt, 5);

                                        function.addInstruction(InstructionFactory.add2(dr, sr1, imm5));
                                    },
                                }
                            }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "AND")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: AND logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "BR")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: BR logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "JMP")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: JMP logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "CALL")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: CALL logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "LD")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: LD logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "LDI")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: LDI logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "LDR")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: LDR logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "LEA")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: LEA logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "NOT")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: NOT logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "ST")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: ST logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "STI")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: STI logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "STR")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: STR logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "TRAP")) {
                            self.token.ptr = 0;

                            return error.NotImplemented;
                            // while (true) {
                            //     // TODO: TRAP logic
                            // }
                        } else if (std.mem.eql(u8, self.token.buff[0..self.token.ptr], "JSR")) {
                            // TODO: JSR error message
                            return ParserError.InvalidSyntax;
                        } else {
                            // TODO: Handle Label

                            return ParserError.InvalidSyntax;
                        }

                        self.token.ptr = 0;
                        continue;
                    }

                    if (!std.ascii.isASCII(byte)) {
                        return ParserError.InvalidSyntax;
                    }

                    if (byte == '}') {
                        if (isStart) {
                            function.addInstruction(InstructionFactory.trap(.HALT));

                            self.functions.insert(0, function);
                        } else {
                            function.addInstruction(InstructionFactory.ldr(.R7, .R6, 0));
                            function.addInstruction(InstructionFactory.add2(.R6, .R6, 1));
                            function.addInstruction(InstructionFactory.ret());

                            self.functions.append(function);
                        }
                        return;
                    }

                    self.token.append(byte);
                },
            }
        }
    }

    fn parseGlobalData(self: *Parser) !void {
        while (true) {
            const byte = try self.getbyte();

            switch (byte) {}
        }
    }

    fn handleComment(self: *Parser) !void {
        const nextByte = try self.getbyte();
        if (nextByte != '\\') {
            return ParserError.InvalidSyntax;
        }

        try self.readUntilNewline();
    }

    fn parseAndExtractString(self: *Parser, strDelimiter: u8) !String {
        if (strDelimiter != '"' and strDelimiter != '\'') {
            return ParserError.UnexpectedError;
        }

        const str: String = String.initFast(self.allocator);

        var escape: bool = false;

        while (true) {
            var byte: u8 = try self.getbyte();

            if (escape) {
                escape = false;
                switch (byte) {
                    'x' => {
                        var hexLiteral: [4]u8 = .{ '0', 'x', '0', '0' };

                        const bytes = try self.getbytes(2);
                        defer self.allocator.free(bytes);

                        std.mem.copyForwards(u8, hexLiteral[2..4], bytes);

                        byte = std.fmt.parseInt(u8, hexLiteral[0..4], 16) catch |err| {
                            switch (err) {
                                err.ParseIntError => {
                                    return ParserError.InvalidSyntax;
                                },
                                else => return err,
                            }
                        };
                    },
                    '\\', strDelimiter => {},
                    else => {
                        return ParserError.InvalidSyntax;
                    },
                }
            } else if (strDelimiter == byte) {
                return str;
            } else if (byte == '\\') {
                escape = true;
                continue;
            }

            try str.append(byte);
        }
    }

    /// Parsing integer from file asm
    /// param fc: accept integer character '0'~'9' and '-'
    fn parseAndExtractInteger(self: *Parser, fc: u8) !i32 {
        var base: u8 = 10;
        const buf: String = String.init(self.allocator, 128);

        const isMinus: bool = fc == '-';

        if (isMinus) {
            const fc1: u8 = try self.getbyte();

            if (!std.ascii.isDigit(fc1)) {
                return ParserError.InvalidSyntax;
            }

            buf.append(fc1);
        } else {
            if (!std.ascii.isDigit(fc)) {
                return ParserError.InvalidSyntax;
            }

            buf.append(fc);
        }

        while (true) {
            const byte: u8 = try self.getbyte();

            if (buf.ptr == 1 and fc == '0') {
                switch (byte) {
                    'x' => base = 16,
                    'o' => base = 8,
                    'b' => base = 2,
                    '0'...'9' => {},
                    else => {
                        return ParserError.InvalidSyntax;
                    },
                }
            } else if (byte == ' ' or byte == '\t') {
                if (isMinus) {
                    return (try std.fmt.parseInt(i32, buf.buff[0..buf.ptr], base)) * -1;
                } else {
                    return try std.fmt.parseInt(i32, buf.buff[0..buf.ptr], base);
                }
            } else if ((base == 16 and !std.ascii.isHex(byte)) or (base == 10 and !std.ascii.isDigit(byte)) or (base == 8 and !checkOctal(byte)) or (base == 2 and !checkBiner(byte))) {
                return ParserError.InvalidSyntax;
            }

            buf.append(byte);
        }
    }

    fn parseAndExtractRegister(self: *Parser, fc: u8) !Register {
        if (fc == 'R') {
            return ParserError.InvalidSyntax;
        }

        const numR = try self.parseAndExtractInteger(try self.getbyte());

        if (numR < 0 or numR > 7) {
            return ParserError.InvalidSyntax;
        }

        return @enumFromInt(numR);
    }

    pub fn finalize(self: *Parser) !type {
        defer self.cleanup(); // end with cleanup

        return;
    }

    fn getbyte(self: *Parser) !u8 {
        const byte: u8 = try self.reader.readByte();

        if (self.lineEnd) {
            self.lineEnd = false;
            self.line.ptr = 0;
            self.numLine += 1;
        }

        if (byte == '\n') {
            self.lineEnd = true;
        } else {
            self.line.append(byte);
        }

        return byte;
    }

    fn getbytes(self: *Parser, num: usize) ![]u8 {
        const ret: []u8 = try self.allocator.alloc(u8, num);
        for (0..num) |i| {
            ret[i] = try self.getbyte();
        }
        return ret;
    }

    fn readUntil(self: *Parser, delimiter: u8) ![]u8 {
        self.tempBufer.ptr = 0;

        while (true) {
            if (self.tempBufer.leftSize() < 1) {
                try self.tempBufer.resizeFast();
            }

            const byte: u8 = self.getbyte() catch |err| {
                if (err == error.EndOFStream) {
                    return self.tempBufer.buff[0..self.tempBufer.ptr];
                }
                return err;
            };

            self.tempBufer.append(byte);

            if (byte == delimiter) {
                return self.tempBufer.buff[0..self.tempBufer.ptr];
            }
        }
    }

    fn readUntilNewline(self: *Parser) ![]u8 {
        try self.readUntil('\n');
    }
};
