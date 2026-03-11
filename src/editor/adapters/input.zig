//! Input adapter - abstract interface for keyboard input
const std = @import("std");
const types = @import("types.zig");
const Key = types.Key;
const InputError = types.InputError;

/// Input VTable - adapter implementations must provide these functions
pub const InputVTable = struct {
    /// Read a single key press (blocking)
    readKey: *const fn (*anyopaque) InputError!Key,

    /// Clean up resources
    deinit: *const fn (*anyopaque) void,
};

/// Input interface - wraps any input adapter implementation
pub const Input = struct {
    ptr: *anyopaque,
    vtable: *const InputVTable,

    const Self = @This();

    /// Create Input wrapper from any implementation
    pub fn init(ptr: anytype, vtable: *const InputVTable) Self {
        return .{
            .ptr = @ptrCast(@alignCast(ptr)),
            .vtable = vtable,
        };
    }

    /// Clean up resources
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }

    /// Read a single key press
    pub fn readKey(self: *Self) InputError!Key {
        return self.vtable.readKey(self.ptr);
    }
};

/// NativeInput - real stdin input implementation
pub const NativeInput = struct {
    stdin_file: std.fs.File,

    const Self = @This();

    /// Initialize with stdin
    pub fn init() Self {
        return .{
            .stdin_file = std.fs.File.stdin(),
        };
    }

    /// Read a single key press (blocking)
    pub fn readKey(self: *Self) InputError!Key {
        var buf: [1]u8 = undefined;
        const n = self.stdin_file.read(&buf) catch return InputError.ReadFailed;
        if (n != 1) return InputError.ReadFailed;

        const first_byte = buf[0];

        // Handle escape sequences (arrow keys, etc.)
        if (first_byte == '\x1b') {
            return self.parseEscapeSequence();
        }

        // Handle enter first (both \r and \n for cross-platform)
        // Must be checked before control characters since \r < 32
        if (first_byte == '\r' or first_byte == '\n') {
            return .enter;
        }

        // Handle tab
        if (first_byte == '\t') {
            return .tab;
        }

        // Handle backspace/delete
        if (first_byte == 127) {
            return .backspace;
        }

        // Handle control characters (Ctrl+ key) - after special keys
        if (first_byte < 32) {
            return parseControlCharacter(first_byte);
        }

        // UTF-8 character: read remaining bytes
        const seq_len = std.unicode.utf8ByteSequenceLength(first_byte) catch return .unknown;

        var char_buf: [4]u8 = undefined;
        char_buf[0] = first_byte;
        char_buf[1] = 0;
        char_buf[2] = 0;
        char_buf[3] = 0;

        if (seq_len > 1) {
            const bytes_read = self.stdin_file.read(char_buf[1..seq_len]) catch return .unknown;
            if (bytes_read != seq_len - 1) return .unknown;
        }

        // Validate UTF-8
        const slice = char_buf[0..seq_len];
        if (!std.unicode.utf8ValidateSlice(slice)) {
            return .unknown;
        }

        return Key{ .character = char_buf };
    }

    fn parseEscapeSequence(self: *Self) InputError!Key {
        var esc_buf: [1]u8 = undefined;

        // Try to read '['
        const n = self.stdin_file.read(&esc_buf) catch return .escape;
        if (n != 1) return .escape;

        const next = esc_buf[0];

        if (next != '[') {
            // Not an escape sequence, just ESC
            return .escape;
        }

        // Read the command byte
        const cmd_byte = self.stdin_file.read(&esc_buf) catch return .escape;
        if (cmd_byte != 1) return .escape;

        const cmd = esc_buf[0];

        return switch (cmd) {
            'A' => .arrow_up,
            'B' => .arrow_down,
            'C' => .arrow_right,
            'D' => .arrow_left,
            'H' => .home,
            'F' => .end,
            '3' => blk: {
                // Delete key sends "[3~"
                _ = self.stdin_file.read(&esc_buf) catch {};
                break :blk .delete;
            },
            '5' => blk: {
                // Page up: "[5~"
                _ = self.stdin_file.read(&esc_buf) catch {};
                break :blk .page_up;
            },
            '6' => blk: {
                // Page down: "[6~"
                _ = self.stdin_file.read(&esc_buf) catch {};
                break :blk .page_down;
            },
            else => .unknown,
        };
    }

    /// Parse control character to Key (public for testing)
    pub fn parseControlCharacter(byte: u8) Key {
        return switch (byte) {
            3 => .ctrl_c,
            19 => .ctrl_s,
            17 => .ctrl_q,
            6 => .ctrl_f,
            else => .unknown,
        };
    }

    /// Clean up (no-op for stdin)
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // ========================================================================
    // VTable implementation
    // ========================================================================

    /// Static VTable for Input interface (must be static to avoid dangling pointer)
    pub const vtable = InputVTable{
        .readKey = vtableReadKey,
        .deinit = vtableDeinit,
    };

    /// Create Input wrapper
    pub fn input(self: *Self) Input {
        return Input.init(self, @constCast(&vtable));
    }

    fn vtableReadKey(ptr: *anyopaque) InputError!Key {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.readKey();
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "NativeInput - parse control characters" {
    try std.testing.expectEqual(Key.ctrl_c, NativeInput.parseControlCharacter(3));
    try std.testing.expectEqual(Key.ctrl_s, NativeInput.parseControlCharacter(19));
    try std.testing.expectEqual(Key.ctrl_q, NativeInput.parseControlCharacter(17));
    try std.testing.expectEqual(Key.ctrl_f, NativeInput.parseControlCharacter(6));
    try std.testing.expectEqual(Key.unknown, NativeInput.parseControlCharacter(0));
    try std.testing.expectEqual(Key.unknown, NativeInput.parseControlCharacter(1));
}

test "Key - isCharacter" {
    const char_key = Key{ .character = .{ 'A', 0, 0, 0 } };
    try std.testing.expect(char_key.isCharacter());

    const arrow_key = Key.arrow_up;
    try std.testing.expect(!arrow_key.isCharacter());
}

test "Key - getCharacter" {
    const char_key = Key{ .character = .{ 'A', 'B', 0, 0 } };
    const chars = char_key.getCharacter().?;
    try std.testing.expectEqual(@as(usize, 2), chars.len);
    try std.testing.expectEqual(@as(u8, 'A'), chars[0]);
    try std.testing.expectEqual(@as(u8, 'B'), chars[1]);

    const arrow_key = Key.arrow_up;
    try std.testing.expect(arrow_key.getCharacter() == null);
}

test "NativeInput - init" {
    var native = NativeInput.init();
    const inp = native.input();
    _ = inp;
}
