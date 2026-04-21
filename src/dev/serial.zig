const root = @import("root");
const arch = root.arch;

var uart: *volatile [8]u8 = undefined;

pub fn init(addr: usize) void {
    uart = @as(*volatile [8]u8, @ptrFromInt(addr));

    // 1. Disable interrupts
    uart[1] = 0x00; 

    // 2. Set LCR: 8 bits, no parity, 1 stop bit
    uart[3] = 0x03; 

    // 3. Enable and clear FIFOs
    uart[2] = 0x01; 
}

pub fn print(msg: []const u8) void {
    
    for (msg) |c| {
        // Wait until THR (Transmit Holding Register) is empty
        // Check LSR (Line Status Register) bit 5
        while ((uart[5] & 0x20) == 0) {
            arch.instr.pause();
        }
        uart[0] = c;
    }
}
