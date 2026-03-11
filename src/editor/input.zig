//! Key reading and parsing for terminal input
const std = @import("std");

pub const Key = union(enum) {
    // Control keys
    ctrl_c, // Exit
    ctrl_s, // Save
    ctrl_q, // Quit (with prompt)
    ctrl_f, // Find (future)

    // Navigation
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    home,
    end,
    page_up,
    page_down,

    // Editing
    escape,
    enter,
    backspace,
    delete,
    tab,

    // UTF-8 character (1-4 bytes stored inline)
    character: [4]u8,

    // Unknown/unsupported
    unknown,
};

pub const Input = struct {
    stdin_file: std.fs.File,
    read_buffer: [16]u8,

    pub fn init() Input {
        return .{
            .stdin_file = std.fs.File.stdin(),
            .read_buffer = undefined,
        };
    }

    /// Read a single key press (blocking)
    pub fn readKey(self: *Input) !Key {
        var buf: [1]u8 = undefined;
        const n = self.stdin_file.read(&buf) catch return .unknown;
        if (n != 1) return .unknown;

        const first_byte = buf[0];

        // Handle escape sequences (arrow keys, etc.)
        if (first_byte == '\x1b') {
            return self.parseEscapeSequence();
        }

        // Handle control characters (Ctrl+ key)
        if (first_byte < 32) {
            return parseControlCharacter(first_byte);
        }

        // Handle backspace/delete
        if (first_byte == 127) {
            return .backspace;
        }

        // Handle enter
        if (first_byte == '\n') {
            return .enter;
        }

        // Handle tab
        if (first_byte == '\t') {
            return .tab;
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

    fn parseEscapeSequence(self: *Input) !Key {
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
                _ = self.stdin_file.read(&esc_buf) catch {}; // consume '~'
                break :blk .delete;
            },
            '5' => blk: {
                // Page up: "[5~"
                _ = self.stdin_file.read(&esc_buf) catch {}; // consume '~'
                break :blk .page_up;
            },
            '6' => blk: {
                // Page down: "[6~"
                _ = self.stdin_file.read(&esc_buf) catch {}; // consume '~'
                break :blk .page_down;
            },
            else => .unknown,
        };
    }

    /// Parse control character to Key (public for testing)
    pub fn parseControlCharacter(byte: u8) Key {
        // Ctrl+ keys: Ctrl+C = 3, Ctrl+S = 19, etc.
        return switch (byte) {
            3 => .ctrl_c,
            19 => .ctrl_s,
            17 => .ctrl_q,
            6 => .ctrl_f,
            else => .unknown,
        };
    }
};

test "parse control characters" {
    // Test control character parsing via the public parseControlCharacter function
    // Ctrl+C = byte 3, Ctrl+S = byte 19, Ctrl+Q = byte 17, Ctrl+F = byte 6
    try std.testing.expectEqual(Key.ctrl_c, Input.parseControlCharacter(3));
    try std.testing.expectEqual(Key.ctrl_s, Input.parseControlCharacter(19));
    try std.testing.expectEqual(Key.ctrl_q, Input.parseControlCharacter(17));
    try std.testing.expectEqual(Key.ctrl_f, Input.parseControlCharacter(6));
    try std.testing.expectEqual(Key.unknown, Input.parseControlCharacter(0));
    try std.testing.expectEqual(Key.unknown, Input.parseControlCharacter(1));
}

test "utf8 byte sequence length" {
    // Test UTF-8 byte sequence length detection
    const seq_len1 = std.unicode.utf8ByteSequenceLength(0x41); // 'A' - 1 byte
    try std.testing.expectEqual(@as(usize, 1), seq_len1);

    const seq_len2 = std.unicode.utf8ByteSequenceLength(0xC3); // Start of 2-byte sequence
    try std.testing.expectEqual(@as(usize, 2), seq_len2 catch 0);

    const seq_len3 = std.unicode.utf8ByteSequenceLength(0xE4); // Start of 3-byte sequence
    try std.testing.expectEqual(@as(usize, 3), seq_len3 catch 0);

    const seq_len4 = std.unicode.utf8ByteSequenceLength(0xF0); // Start of 4-byte sequence
    try std.testing.expectEqual(@as(usize, 4), seq_len4 catch 0);
}

test "Key union - character storage" {
    var key = Key{ .character = .{ 'A', 0, 0, 0 } };
    try std.testing.expectEqual(@as(u8, 'A'), key.character[0]);

    // Multi-byte UTF-8 (é = 0xC3 0xA9)
    key = Key{ .character = .{ 0xC3, 0xA9, 0, 0 } };
    try std.testing.expectEqual(@as(u8, 0xC3), key.character[0]);
    try std.testing.expectEqual(@as(u8, 0xA9), key.character[1]);
}

test "Input.init" {
    const input = Input.init();
    try std.testing.expect(input.stdin_file.handle >= 0);
}
