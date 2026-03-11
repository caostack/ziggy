# Zig 编程语言

## 核心概念

Zig 是通用系统编程语言，追求 **健壮、最优、可复用**。

**设计哲学**:
1. 没有隐藏控制流 - 代码做什么就是什么
2. 没有隐藏内存分配 - allocator 显式传递
3. comptime 编译时执行 - 泛型、条件编译都用它

---

## Zig 0.15 快速上手

### ArrayList (显式传递 allocator)

```zig
var list: std.ArrayList(T) = .{};  // 空初始化
defer list.deinit(allocator);       // 需要 allocator
try list.append(allocator, item);   // 每次操作需要 allocator
```

### Optional Types (?T)

```zig
const maybe: ?i32 = null;
if (maybe) |value| { /* 使用 value */ }
const v = maybe orelse 0;  // 提供默认值
const v = maybe.?;         // 确定非 null 时快捷解包
```

### Error Unions (!T)

```zig
fn mightFail() !i32 {
    return error.SomethingWrong;
}
const result = try mightFail();        // 自动传播错误
const result = mightFail() catch 0;    // 提供默认值
const result = mightFail() catch |err| switch (err) { ... };  // 精确处理
```

### Comptime 泛型

```zig
fn Stack(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        fn init(allocator: std.mem.Allocator) Stack(T) { ... }
    };
}
var stack = Stack(i32).init(allocator);
```

### 条件编译 (无预处理器)

```zig
const builtin = @import("builtin");
if (builtin.mode == .Debug) { /* debug 代码 */ }
if (builtin.target.os.tag == .windows) { /* Windows 代码 */ }
comptime { std.debug.assert(@sizeOf(usize) == 8); }  // 编译时断言
```

---

## Zig 0.15 踩坑记录

| 问题 | 解决方案 |
|------|----------|
| `ArrayList.init(allocator)` 不存在 | 用 `.{}` 空初始化 |
| `append(item)` 缺参数 | 现在是 `append(allocator, item)` |
| Type 标签 `.Int` 报错 | 现在小写: `.int`, `.@"struct"` |
| `print("{}", .{slice})` 报错 | 必须用 `{s}` 或 `{any}` |
| `var` 变量报 "never mutated" | 改用 `const` |

---

## 类型内省

```zig
switch (@typeInfo(T)) {
    .int => |info| { /* info.bits, info.signedness */ },
    .float => |info| { /* info.bits */ },
    .pointer => |info| { /* info.child, info.size */ },
    .@"struct" => |info| { /* info.fields */ },
    .@"enum" => |info| { /* info.fields */ },
    else => {},
}
```

---

## 参考资源

- 官方文档: https://ziglang.org/documentation/master/
- Zig 0.15 迁移指南: https://gist.github.com/pmarreck/44d95e869036027f9edf332ce9a94583
- Ziggit 社区: https://ziggit.dev/
- 学习代码: `.learning/zig/mastery/artifacts/`
