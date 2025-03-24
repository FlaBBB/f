const std = @import("std");
const builtin = @import("builtin");

const term = @import("./term.zig");
const lc3 = @import("./lc3.zig");
const LC3 = lc3.LC3;

var originalTerminalState: term.TerminalState = undefined;
var arenaForCleanup: std.mem.Allocator = undefined;

fn handleSigInt(_: i32) callconv(.C) void {
    term.setTermState(originalTerminalState, arenaForCleanup);
    std.process.exit(0);
}

fn readFile(filePath: []const u8, arena: std.mem.Allocator) ![]u16 {
    const file = std.fs.cwd().openFile(filePath, .{}) catch |err| {
        return err;
    };
    defer file.close();
    const reader = file.reader();

    var origin = try reader.readInt(u16, std.builtin.Endian.little);
    origin = @byteSwap(origin);

    const maxRead = @as(u32, @intCast(lc3.MEMORY_MAX)) - @as(u32, @intCast(origin));

    const bytes: []u16 = try arena.alloc(u16, lc3.MEMORY_MAX);
    @memset(bytes, 0);

    var memIdx = origin;
    while (memIdx <= maxRead) {
        const word = reader.readInt(u16, std.builtin.Endian.little) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        };
        bytes[memIdx] = @byteSwap(word);
        memIdx += 1;
    }
    return bytes;
}

fn loadRomEmbedd(comptime embeddContent: []const u8, arena: std.mem.Allocator) ![]u16 {
    var origin: u16 = std.mem.readInt(u16, embeddContent[0..2], .little);
    origin = @byteSwap(origin);

    const bytes: []u16 = try arena.alloc(u16, lc3.MEMORY_MAX);
    @memset(bytes, 0);

    const contentSize = (embeddContent.len - 2) / 2;

    var memIdx = origin;
    var i: usize = 0;
    while (i < contentSize and memIdx < lc3.MEMORY_MAX) : (i += 1) {
        const ptr: *const [2]u8 = @ptrCast(embeddContent[i * 2 + 2 .. i * 2 + 4]);
        const word = std.mem.readInt(u16, ptr, .little);
        bytes[memIdx] = @byteSwap(word);
        memIdx += 1;
    }

    return bytes;
}

pub fn main() !void {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = generalPurposeAllocator.allocator();

    var arenaInstance = std.heap.ArenaAllocator.init(gpa);
    defer arenaInstance.deinit();
    const arena = arenaInstance.allocator();

    arenaForCleanup = arena;

    // set terminal mode
    originalTerminalState = try term.disableInputBuffering(arena);
    defer term.setTermState(originalTerminalState, arena);

    if (builtin.os.tag == .linux) {
        const sa = std.os.linux.Sigaction{ .handler = .{
            .handler = handleSigInt,
        }, .mask = [_]u32{0} ** 32, .flags = 0 };
        _ = std.os.linux.sigaction(2, &sa, null);
    }

    const rom = loadRomEmbedd(@embedFile("rom"), arena) catch |err| {
        std.debug.print("Error load rom: {}\n", .{err});
        return err;
    };

    var vm = LC3.init();
    vm.loadRom(rom);
    vm.virtualize();
}
