const String = @import("./types.zig").String;

pub const ParserError = error{
    NotFoundWaitingList,
    InvalidSyntax,
    UnexpectedError,
    IntegerOverflow,
};

pub var InvalidSyntaxContext = struct {
    at: u64,
    numLine: u64,
    line: String,
    message: []const u8
};