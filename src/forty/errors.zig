pub const ForthError = error{
    TooManyEntries,
    NotFound,
    OverFlow,
    UnderFlow,
    BadOperation,
    WordReadError,
    ParseError,
    FormatError,
    OutOfMemory,
    AlreadyCompiling,
    NotCompiling,
    EOF,
};
