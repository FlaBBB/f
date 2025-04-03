pub const MappedRegister = enum(u16) {
    /// Keyboard status
    KBSR = 0xFE00,

    /// Keyboard data
    KBDR = 0xFE02,
};
