# Ziggy 团队约定

## 🎯 我们遵循的原则

> "没有绝对的标准，只有团队的共识"

---

## 📋 代码约定

### 1. 资源管理

```zig
// ✅ 我们这样做
fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    return content;
}

// ❌ 避免这样做
fn readFileBad(path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    // 忘记 close()!
    return file.readToEndAlloc(std.heap.page_allocator, 1024);
}
```

**原则**: 获取资源后立即用 `defer` 标记清理

---

### 2. 内存管理

```zig
// ✅ 显式分配 + defer 清理
fn processData(allocator: std.mem.Allocator) !void {
    const buffer = try allocator.alloc(u8, 4096);
    defer allocator.free(buffer);

    // 处理数据...
}

// ❌ 避免 ArrayList（隐藏分配）
// var list = std.ArrayList(i32).init(allocator);
```

**原则**: 内存分配必须显式，让调用者决定使用什么 allocator

---

### 3. 错误处理

```zig
// ✅ 明确的错误集
const ParseError = error{
    InvalidCharacter,
    UnexpectedEOF,
};

fn parseInt(str: []const u8) ParseError!i32 {
    // 处理错误...
}
```

**原则**: 使用明确的错误集，让错误可见

---

### 4. 数据结构

```zig
// ✅ 简单的 struct
const Buffer = struct {
    data: []u8,
    capacity: usize,

    pub fn init(allocator: Allocator) !Buffer {
        // ...
    }
};

// ❌ 避免 OOP 抽象
// trait Interface { }
// impl Interface for Buffer { }
```

**原则**: Zig 不是 OOP，用 struct + 函数

---

## 🧪 测试约定

```zig
test "buffer insert/delete" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.init(allocator, 100);
    defer buffer.deinit();

    try buffer.insert("Hello");
    try std.testing.expectEqual(@as(usize, 5), buffer.gap_start);
}
```

**原则**:
- 测试用 GPA 检测内存泄漏
- 每个公共函数都应该有测试

---

## 📖 命名约定

### 类型
```zig
// ✅ PascalCase
const Buffer = struct { ... };
const ParseError = error { ... };
const FileIO = struct { ... };
```

### 函数
```zig
// ✅ camelCase
pub fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    // ...
}

fn insertChar(self: *Buffer, char: u8) !void {
    // ...
}
```

### 常量
```zig
// ✅ UPPER_SNAKE_CASE 或 camelCase
const MAX_BUFFER_SIZE = 4096;
const default_timeout = 30;
```

---

## 🎓 学习资源

### 参考代码
- **Zig 标准库** (zig/std/) - 最好的学习材料
- **Andrew Kelley 的项目** - Zig 创始人的代码风格
- **Ziggit 社区** - 看看大家如何讨论风格问题

### 社区讨论
- [Ziggit 论坛](https://ziggit.dev/)
- [Zig Show](https://zig.show/)

---

## 🤝 代码审查流程

### 提交 PR 前的清单

- [ ] 代码编译通过
- [ ] 测试全部通过
- [ ] 自己审查一遍代码
- [ ] 添加必要的注释
- [ ] 更新文档（如果需要）

### PR 审查时关注

- [ ] 资源管理：所有资源都有 defer 清理
- [ ] 内存管理：没有隐藏分配
- [ ] 错误处理：错误都被正确处理
- [ ] 代码简洁：没有过度抽象
- [ ] 可读性：代码意图清晰

---

## 🔄 持续改进

这个文档是活的！当团队发现更好的做法时：

1. 讨论并达成共识
2. 更新这个文档
3. 在团队中分享知识

---

**记住：Zig 没有绝对的对错，只有团队的共识！** 🎯
