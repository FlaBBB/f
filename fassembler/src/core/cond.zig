pub const ConditionFlag = enum(u16) {
    /// Positive Flag
    POS = 1 << 0,

    /// Zero Flag
    ZRO = 1 << 1,

    /// Negative Flag
    NEG = 1 << 2,
};
