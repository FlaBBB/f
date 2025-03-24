const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const termios = linux.termios;
const windows = std.os.windows;
const kernel32 = windows.kernel32;

pub fn checkKey() bool {
    switch (comptime builtin.os.tag) {
        .linux => {
            var fds = [_]std.os.linux.pollfd{
                .{
                    .fd = std.io.getStdIn().handle,
                    .events = std.os.linux.POLL.IN,
                    .revents = 0,
                },
            };
            const ret = std.os.linux.poll(&fds, 1, 0); // 0ms timeout, non-blocking
            const res = (ret > 0) and (fds[0].revents & std.os.linux.POLL.IN != 0);
            return res;
        },
        .windows => {
            const c = @cImport({
                @cInclude("conio.h");
            });
            const handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch unreachable;

            // WaitForSingleObject in Zig's std lib, WaitForSingleObject returns no
            // error when there is a character to read.
            windows.WaitForSingleObject(handle, 1000) catch |err| switch (err) {
                windows.WaitForSingleObjectError.WaitTimeOut => return false,
                windows.WaitForSingleObjectError.WaitAbandoned => return false,
                windows.WaitForSingleObjectError.Unexpected => return false,
            };
            const res = c._kbhit() != 0;
            return res;
        },
        else => {
            return false;
        },
    }
}

pub const TerminalState = union(enum) {
    none: void,
    linux: *std.os.linux.termios,
    windows: u32,
};

pub fn disableInputBuffering(allocator: std.mem.Allocator) !TerminalState {
    var terminal_state: TerminalState = .none;
    switch (builtin.os.tag) {
        .linux => {
            const input = try openInputTTY(allocator);
            var st = try disableInputBufferingLinux(input);
            terminal_state = TerminalState{ .linux = &st };
        },
        .windows => {
            const st = disableInputBufferingWindows();
            terminal_state = TerminalState{ .windows = st };
        },
        else => @panic("unsupported platform"),
    }
    return terminal_state;
}

fn disableInputBufferingLinux(in: *std.fs.File) !termios {
    var t = termios{
        .iflag = .{},
        .oflag = .{},
        .cflag = .{},
        .lflag = .{},
        .cc = std.mem.zeroes([32]u8),
        .line = 0,
        .ispeed = linux.speed_t.B38400,
        .ospeed = linux.speed_t.B38400,
    };

    // Get current terminal attributes
    _ = linux.tcgetattr(in.handle, &t);
    const original_state = t;

    t.lflag.ECHO = false;
    t.lflag.ICANON = false;

    setAttr(in, &t);

    return original_state;
}

fn disableInputBufferingWindows() windows.DWORD {
    const in = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch unreachable;
    const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
    const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
    var old_mode: windows.DWORD = 0;

    // ignoring errors for now
    _ = kernel32.GetConsoleMode(in, &old_mode);
    const new_mode = old_mode & ~ENABLE_ECHO_INPUT & ~ENABLE_LINE_INPUT;
    _ = kernel32.SetConsoleMode(in, new_mode);
    return old_mode;
}

pub fn openInputTTY(allocator: std.mem.Allocator) !*std.fs.File {
    const f = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_only });
    const p = try allocator.create(std.fs.File);
    p.* = f;
    return p;
}

pub fn setTermState(st: TerminalState, allocator: std.mem.Allocator) void {
    switch (builtin.os.tag) {
        .linux => {
            const input = openInputTTY(allocator) catch unreachable;
            setAttr(input, st.linux);
        },
        .windows => {
            const in = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch unreachable;
            _ = kernel32.SetConsoleMode(in, st.windows);
        },
        else => @panic("unsupported platform"),
    }
}

// set linux terminal attr
fn setAttr(in: *std.fs.File, t: *linux.termios) void {
    _ = linux.tcsetattr(in.handle, linux.TCSA.NOW, t);
}
