# Zig 设计哲学与代码规范

## 🎯 Zig 核心设计哲学

Zig 是一门**显式、手动控制、性能透明**的系统编程语言。理解并遵循这些哲学对编写高质量 Zig 代码至关重要。

---

## 1️⃣ 显式优于隐式 (Explicit > Implicit)

### 原则
Zig 讨厌"魔法"和隐式行为。一切都应该显式声明。

### ✅ 正确示例
```zig
// 显式的内存分配
const data = try allocator.alloc(u8, 1024);
defer allocator.free(data);

// 显式的错误处理
const file = try std.fs.cwd().openFile("test.txt", .{});
defer file.close();
```

### ❌ 错误示例
```zig
// ❌ 隐藏分配的 ArrayList
var list = std.ArrayList(i32).init(allocator);
try list.append(42);  // 内部隐藏了分配

// ❌ 隐藏错误的 unwrap
const value = maybe_value orelse return;  // 隐藏了错误处理
```

### 质量标准
- ✅ 所有内存分配都必须显式：`allocator.alloc(u8, size)`
- ✅ 所有错误都必须显式处理：`try`, `catch`, `if`
- ❌ 不使用 `ArrayList`（隐藏分配）
- ❌ 不使用 `unwrap()`, `orelse return`（隐藏错误）

---

## 2️⃣ 手动资源管理

### 原则
Zig 不使用 GC 或 RAII，资源管理必须手动但系统化。

### ✅ 正确示例
```zig
// 使用 defer 确保清理
const file = try std.fs.cwd().openFile("test.txt", .{});
defer file.close();  // 总是会执行

const data = try allocator.alloc(u8, 1024);
defer allocator.free(data);

// 错误路径的资源清理
const data = try allocator.alloc(u8, 1024);
errdefer allocator.free(data);  // 只在错误时清理

try processData(data);  // 成功时需要手动管理
allocator.free(data);  // 成功路径的清理
```

### ❌ 错误示例
```zig
// ❌ 忘记释放资源
const data = try allocator.alloc(u8, 1024);
processData(data);
// 缺少 defer allocator.free(data)
```

### 质量标准
- ✅ 每个获取资源的操作后都有 `defer`
- ✅ 使用 `errdefer` 处理错误路径
- ❌ 不允许资源泄漏

---

## 3️⃣ 编译时计算 (Comptime)

### 原则
尽可能在编译时完成工作，减少运行时开销。

### ✅ 正确示例
```zig
// 编译时类型检查
comptime {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("T must be a struct");
    }
}

// 编译时生成查找表
comptime const lookup_table = generateLookupTable();

// 编译时验证
const assert_ok = comptime assertSizeEquals(MyStruct, 32);
```

### ❌ 错误示例
```zig
// ❌ 运行时可以做编译时做的事
const value = getAtRuntime();  // 如果可以在编译时计算，就应该用 comptime
```

### 质量标准
- ✅ 使用 `comptime` 进行类型检查和验证
- ✅ 使用 `@typeInfo` 进行类型反射
- ✅ 使用 `@setEvalBranchQuota` 增加编译时评估限制
- ❌ 避免运行时可以完成的计算

---

## 4️⃣ 无隐藏分配 (No Hidden Allocations)

### 原则
所有内存分配都应该可见和可控。

### ✅ 正确示例
```zig
// 显式分配
const buffer = try allocator.alloc(u8, 4096);
defer allocator.free(buffer);

// 使用固定缓冲区（栈分配）
var buffer: [4096]u8 = undefined;

// 使用 Arena 管理一组分配
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();
```

### ❌ 错误示例
```zig
// ❌ ArrayList 隐藏分配
var list = std.ArrayList(i32).init(allocator);
try list.append(42);  // 内部分配

// ❌ std.fmt.allocPrint（隐藏分配）
const msg = try std.fmt.allocPrint(allocator, "Hello {s}", .{name});
// 应该使用固定缓冲区
```

### 质量标准
- ✅ 所有分配都显式传递 `Allocator`
- ✅ 优先使用栈分配（固定数组）
- ✅ 使用 `ArenaAllocator` 管理临时分配
- ❌ 避免 `std.ArrayList`
- ❌ 避免隐藏分配的格式化函数

---

## 5️⃣ 性能透明 (Performance Transparency)

### 原则
代码应该能清楚看出性能特征。

### ✅ 正确示例
```zig
// 使用切片避免拷贝
fn process(data: []const u8) void {
    // 直接使用切片，零拷贝
}

// 显式的内存布局
const Point = struct {
    x: f64,
    y: f64,
};

// 编译时可知的性能
comptime {
    @asert(@sizeOf(Point) == 16);
}
```

### ❌ 错误示例
```zig
// ❌ 不必要的拷贝
const data = try allocator.dupe(u8, original);
process(data);
allocator.free(data);
// 应该传递切片
```

### 质量标准
- ✅ 优先使用切片 (`[]u8`) 而非拷贝
- ✅ 使用 `@sizeOf`, `@alignOf` 了解内存布局
- ✅ 避免不必要的内存拷贝
- ❌ 避免使用 `dupe()` 除非必要

---

## 6️⃣ 简单直接 (Simple and Direct)

### 原则
Zig 不是 OOP 语言，避免过度抽象。

### ✅ 正确示例
```zig
// 使用 struct 和函数
const Buffer = struct {
    data: []u8,
    capacity: usize,

    pub fn init(allocator: Allocator) !Buffer {
        // 直接的实现
    }
};

// 简单的函数调用
const result = process(data);
```

### ❌ 错误示例
```zig
// ❌ OOP 风格的抽象
trait Interface {
    fn process(self);
}

impl Interface for Buffer {
    fn process(self) {
        // 过度抽象
    }
}
```

### 质量标准
- ✅ 使用 `struct` 组织数据
- ✅ 使用简单的函数
- ✅ 避免接口、抽象类等 OOP 概念
- ❌ 避免 trait、class、impl 等模式

---

## 7️⃣ 安全第一 (Safety First)

### 原则
默认安全，可以选择关闭。

### ✅ 正确示例
```zig
// 定义明确的错误集
const ParseError = error{
    InvalidCharacter,
    Overflow,
    UnexpectedEOF,
};

// 使用错误联合类型
fn parseInt(str: []const u8) ParseError!i32 {
    // 显式错误处理
}

// 保持运行时安全检查
zig build -O ReleaseSafe  // 默认安全检查开启
```

### ❌ 错误示例
```zig
// ❌ 过度使用 anytype
fn process(value: anytype) void {
    // 失去类型安全
}

// ❌ 随意关闭安全检查
const safe = @setRuntimeSafety(false);
```

### 质量标准
- ✅ 使用明确的错误集
- ✅ 使用 `!T` 错误联合类型
- ✅ 保持运行时安全检查开启
- ❌ 避免 `anytype`（除非有充分理由）
- ❌ 避免关闭安全检查

---

## 📋 代码审查清单

### 提交前检查

- [ ] 所有内存分配都显式声明
- [ ] 所有错误都被显式处理
- [ ] 每个资源获取后都有 `defer`
- [ ] 使用 `comptime` 进行类型检查
- [ ] 避免使用 `ArrayList`
- [ ] 使用切片而非拷贝
- [ ] 使用 `struct` 而非 OOP 抽象
- [ ] 定义明确的错误集
- [ ] 代码能编译通过
- [ ] 所有测试通过

---

## 🎓 学习资源

- [Zig 官方文档](https://ziglang.org/documentation/master/)
- [Zig 风格指南](https://ziglang.org/documentation/master/#Style-Guide)
- [Zig 标准库源码](https://github.com/ziglang/zig)
- [Zig 学习指南](https://zig.guide/)

---

## 🚨 违反 Zig 哲学的后果

1. **代码审查被拒绝** - 不符合 Zig 哲学的代码不会被合并
2. **质量问题** - 隐藏的分配、错误处理导致资源泄漏
3. **性能问题** - 不必要的拷贝、运行时开销
4. **维护困难** - 过度抽象、隐式行为难以理解

---

**记住：Zig 的哲学是"显式、手动、透明"。遵循这些原则，写出高质量的 Zig 代码！🎯**
