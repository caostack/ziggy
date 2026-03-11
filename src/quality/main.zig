//! 质量门禁工具
//! 对 Zig 代码进行静态分析和质量检查

const std = @import("std");
const QualityGate = @import("checker.zig").QualityGate;
const registerAllCheckers = @import("checkers.zig").registerAllCheckers;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in quality gate!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // 解析命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const target_path = if (args.len > 1) args[1] else "src";

    // 初始化质量门禁
    var gate = try QualityGate.init(allocator);
    defer gate.deinit();

    // 注册所有检查器
    try registerAllCheckers(&gate, allocator);

    const stdout_file = std.fs.File.stdout();

    try stdout_file.writeAll("🚪 Ziggy 质量门禁\n");
    try stdout_file.writeAll("================\n");
    try stdout_file.writeAll("\n");
    try stdout_file.writeAll("⚠️  静态分析可以发现代码问题，但不能替代人工审查\n");
    try stdout_file.writeAll("\n");

    // 运行检查
    var print_buffer: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&print_buffer, "🔍 检查目录: {s}\n\n", .{target_path});
    try stdout_file.writeAll(formatted);

    gate.checkDirectory(target_path) catch |err| {
        const err_msg = try std.fmt.bufPrint(&print_buffer, "错误: 检查目录失败: {any}\n", .{err});
        try stdout_file.writeAll(err_msg);
        return err;
    };

    // 生成报告
    try gate.report(stdout_file);

    // 返回适当的退出码
    if (gate.hasFailures()) {
        try stdout_file.writeAll("\n❌ 质量检查未通过\n");
        std.process.exit(1);
    } else {
        try stdout_file.writeAll("\n✅ 质量检查通过\n");
        try stdout_file.writeAll("\n注意：通过自动检查不代表代码符合 Zig 哲学\n");
        try stdout_file.writeAll("提交 PR 时请确保经过人工代码审查\n");
    }
}
