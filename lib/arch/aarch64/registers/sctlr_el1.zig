/// System Control Register (EL1)
/// See
/// https://developer.arm.com/documentation/ddi0595/2021-12/AArch64-Registers/SCTLR-EL1--System-Control-Register--EL1-?lang=en
const types = @import("../system_register.zig");

pub const layout = packed struct {
    MMU_ENABLE: enum(1) {
        disable = 0,
        enable = 1,
    },
    // Alignment check enable
    A: enum(1) {
        disable = 0,
        enable = 1,
    },
    // Cacheability control
    C: u1,
    // Stack pointer alignment check enable
    SA: u1,
    // Stack pointer alignment check for EL0
    SA0: u1,
    // System instruction memory barrier enable (when EL0 capable of using AArch32)
    CP15BEN: u1 = 0,
    // Non-aligned access trap
    NAA: types.TrapEnableBitN,
    // IT instruction disable at EL0 in AArch32
    ITD: u1 = 0,
    // SETEND instruction disable (when EL0 capable of using AArch32)
    SED: u1 = 1,
    // User mask access
    UMA: u1,
    // Enable EL0 Access to CTX instructions (requires FEAT_SPECRES)
    EnRCTX: u1 = 0,
    // Exception Exit is Context Synchronizing
    EOS: u1,
    // Stage 1 instruction access cacheability control
    I: u1 = 0,
    // Enable pointer authentication
    EnDB: u1 = 0,
    // Trap EL0 execution of DC ZVA instructions
    DZE: types.TrapEnableBitN,
    // Trap EL0 access to CTR_EL0
    UCT: types.TrapEnableBitN,
    // Trap EL0 execution of WFI
    nTWI: types.TrapEnableBitN,
    _unused_reserved_0: u1 = 0,
    // Trap EL0 execution of WFE
    nTWE: types.TrapEnableBitN = 0,
    // Write permission implies execute-never (NX)
    WXN: u1,
    // Trap EL0 access to SCXTNUM_EL0
    TSCXT: types.TrapEnableBitP = .enabled,
    // Implicit error synchronization event enable
    IESB: u1 = 0,
    // Exception Entry is Context Switching
    EIS: u1 = 1,
    // Set Privileged Access Never
    SPAN: u1 = 1,
    // Endianness at EL0
    E0E: u1 = 0,
    // Endianness at EL1
    EE: enum(1) {
        little_endian = 0,
        big_endian = 1,
    },
    // Trap EL0 cache maintenance instructions
    UCI: types.TrapEnableBitN,
    // Enable pointer authentication using APDAKey_EL1
    EnDA: u1 = 0,
    // No trap load multiple and store multiple
    nTLSMD: u1 = 1,
    // Load multiple and store multiple atomicity and ordering
    LSMAOE: u1 = 1,
    // Enable pointer auth using APIBKey_EL1
    EnIB: u1 = 0,
    // Enable pointer auth using APIAKey_EL1 of instr addresses
    EnIA: u1 = 0,
    // Cache maintenince instruction permission
    CMOW: u1 = 0,
    // Memory ocpy and memory set instructions enable
    MSCEn: u1 = 0,
    _unused_reserved_1: u1 = 0,
    // PAC branch type compatibility at EL0
    BT0: u1 = 0,
    // PAC branch type compatibility at EL1
    BT1: u1 = 0,
    // Instuction tag fault synchronization bit
    ITFSB: u1 = 0,
    // Tag check fault in EL0
    TCF0: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect,
    // Tag check fault in EL1
    TCF: enum(u2) {
        no_effect = 0b00,
        synchronous_exception = 0b01,
        asynchronous_accumulate = 0b10,
        exception_on_read_accumulate_on_writes = 0b11,
    } = .no_effect,
    // Allocation tag access in EL0
    ATA0: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = 0,
    // Allocation tag access in EL1
    ATA: enum(u1) {
        not_allowed = 0,
        allowed = 1,
    } = 0,
    // Default SSBS value on exception entry
    DSSBS: u1 = 0,
    // TWE delay enable
    TWEDEn: u1 = 0,
    // TWE Delay
    TWEDEL: u4 = 0,
    // Trap execution of ST64BV instructions
    EnASR: types.TrapEnableBitN,
    // Trap execution of ST64BV0
    EnAS0: types.TrapEnableBitN,
    // Trap execution of LD64B or ST64B
    EnALS: types.TrapEnableBitN,
    // Enhanced privileged access never
    EPAN: u1 = 0,
    _unused_reserved_2: u3 = 0,
    // Non-maskable interrupt enable
    NMI: u1 = 0,
    // SP interrupt mask enable
    SPINTMASK: u1 = 0,
    // Trap "implementation defined" functionality
    TIDCP: u1 = 0,
};