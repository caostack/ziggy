const std = @import("std");
const Editor = @import("ziggy").Editor;

pub fn main() !void {
    // Use GPA for leak detection during development
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const filename = if (args.len > 1) args[1] else null;

    // Initialize editor
    var editor = try Editor.init(allocator, filename);
    defer editor.deinit();

    // Run event loop
    try editor.run();
}

test "simple test" {
    try std.testing.expect(true);
}
