#!/usr/bin/env bash
# Ziggy Quality Gate - Zig Philosophy Edition
# 验证代码质量是否符合 Zig 设计哲学

set -e

echo "🚪 Ziggy Quality Gate - Zig Philosophy Edition"
echo "=============================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 计数器
FAILURES=0
WARNINGS=0
PHILOSPHY_VIOLATIONS=0

# 检查函数
check() {
    local name="$1"
    local command="$2"

    echo -n "🔍 $name... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAILURES++))
        return 1
    fi
}

philosophy_check() {
    local name="$1"
    local command="$2"
    local explanation="$3"

    echo -n "🎯 $name... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo -e "   ${BLUE}ℹ️  $explanation${NC}"
        ((PHILOSPHY_VIOLATIONS++))
        ((FAILURES++))
        return 1
    fi
}

warn() {
    local name="$1"
    local command="$2"

    echo -n "⚠️  $name... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ WARNING${NC}"
        ((WARNINGS++))
        return 0
    fi
}

echo "📋 基础检查"
echo "------------"

# 1. 编译检查
check "编译检查" "zig build"

# 2. 测试检查
check "单元测试" "zig build test"

echo ""
echo "🧹 代码质量检查"
echo "----------------"

# 3. 检查是否有临时文件
warn "无临时文件" "! git ls-files --others --exclude-standard | grep -q '\.swp$\|~$\|\.tmp$'"

# 4. 检查调试代码
warn "无调试代码" "! git grep -q 'std.debug.print' src/"

echo ""
echo "🎯 Zig 设计哲学检查"
echo "=================="

# 哲学 1: 显式优于隐式 (Explicit > Implicit)
philosophy_check "显式内存分配" \
    "! git grep -q 'ArrayList\|std.ArrayList' src/ || \
     git grep -q 'alloc(u8,\|alloc(T' src/" \
    "❌ 不要使用 ArrayList（隐藏分配）"
    "❌ 应该使用显式的内存分配：allocator.alloc(u8, size)"

philosophy_check "显式错误处理" \
    "git grep -q 'try\|catch\|error' src/*.zig" \
    "✅ 所有错误都应该被显式处理"

philosophy_check "禁止隐藏控制流" \
    "! git grep -q 'unwrap()\|orelse[^[:space:]]*return' src/" \
    "❌ 不要使用 unwrap() 或 orelse return（隐藏错误）"

# 哲学 2: 手动资源管理
philosophy_check "使用 defer 清理" \
    "git grep -q 'defer.*deinit\|defer.*close\|defer.*free' src/*.zig" \
    "✅ 资源管理使用 defer 确保清理"

philosophy_check "显式资源生命周期" \
    "! git grep -q 'allocator.*:.*std' src/ || \
     git grep -q 'errdefer' src/*.zig" \
    "✅ 使用 errdefer 处理错误路径的资源清理"

# 哲学 3: 编译时计算
philosophy_check "使用 comptime" \
    "git grep -q 'comptime' src/*.zig" \
    "✅ 利用编译时计算（comptime）减少运行时开销"

philosophy_check "类型信息可见" \
    "! git grep -q 'anytype' src/ || \
     git grep -q '@typeName\|@typeInfo' src/*.zig" \
    "✅ 类型信息应该是显式的，使用具体的类型"

# 哲学 4: 无隐藏分配
warn "避免隐藏分配" \
    "! git grep -q 'std\.fmt\|std\.debug' src/ || \
     git grep -q 'writer.*print' src/*.zig"

philosophy_check "显式分配器传递" \
    "git grep -q 'Allocator' src/*.zig" \
    "✅ 所有分配都显式传递 Allocator 参数"

# 哲学 5: 性能透明
philosophy_check "避免不必要的拷贝" \
    "! git grep -q 'dupe(u8' src/" \
    "✅ 避免不必要的内存拷贝，使用切片而非 dupe"

philosophy_check "使用切片而非数组" \
    "git grep -q '\[\]const u8\|\[\]u8' src/*.zig" \
    "✅ 优先使用切片 ([]u8) 而非指针"

# 哲学 6: 简单直接
philosophy_check "避免过度抽象" \
    "! git grep -q 'interface\|abstract\|class' src/" \
    "✅ Zig 使用 struct 和函数，避免 OOP 风格的抽象"

philosophy_check "直接使用标准库" \
    "! git grep -q 'import.*third.*party\|external.*lib' src/" \
    "✅ 优先使用 Zig 标准库，避免第三方依赖"

# 哲学 7: 安全第一
philosophy_check "定义错误集" \
    "git grep -q 'const.*Error = error' src/*.zig" \
    "✅ 使用明确的错误集而非通用错误"

philosophy_check "边界检查" \
    "! git grep -q '@setRuntimeSafety(false)' src/" \
    "✅ 保持运行时安全检查开启"

echo ""
echo "📏 代码风格检查"
echo "----------------"

# 8. 检查行长度
warn "行长度 < 100 字符" "! git grep -n '.\{101,\}' src/*.zig | grep -v '//'"

# 9. 检查命名规范
philosophy_check "函数命名 camelCase" \
    "! git grep -E 'pub fn [A-Z]' src/*.zig" \
    "❌ 函数名应该使用 camelCase，不是 PascalCase"

philosophy_check "类型命名 PascalCase" \
    "git grep -E 'pub const [a-z].*=' src/*.zig | grep -v 'pub const [a-z]*:' || \
     git grep -E 'pub const [A-Z].*=' src/*.zig | grep 'struct'" \
    "✅ 类型使用 PascalCase"

echo ""
echo "🔒 安全检查"
echo "----------"

# 10. 检查敏感信息
warn "无敏感信息" "! git grep -iq 'password\|secret\|api[_-]key' -- ':!*.md' ':!*.yml' ':!*.sh' ':!quality-gate.sh'"

echo ""
echo "📊 统计信息"
echo "------------"

# 代码行数
LINES_OF_CODE=$(find src -name '*.zig' -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
echo "📝 代码行数: $LINES_OF_CODE"

# 文件数量
FILE_COUNT=$(find src -name '*.zig' 2>/dev/null | wc -l)
echo "📄 文件数量: $FILE_COUNT"

# Zig 特色统计
COMPTIME_COUNT=$(git grep -c 'comptime' src/*.zig 2>/dev/null || echo "0")
echo "⚡ comptime 使用次数: $COMPTIME_COUNT"

ERROR_COUNT=$(git grep -c 'error' src/*.zig 2>/dev/null || echo "0")
echo "⚠️  自定义错误类型: $ERROR_COUNT"

DEFER_COUNT=$(git grep -c 'defer' src/*.zig 2>/dev/null || echo "0")
echo "🧹 defer 使用次数: $DEFER_COUNT"

echo ""
echo "========================================"
echo "质量门禁结果"
echo "========================================"

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！${NC}"
    echo ""
    echo "代码符合 Zig 设计哲学 🎯"
    echo "可以提交 🎉"
    exit 0
else
    echo -e "${RED}✗ $FAILURES 个检查失败${NC}"

    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $WARNINGS 个警告${NC}"
    fi

    if [ $PHILOSPHY_VIOLATIONS -gt 0 ]; then
        echo -e "${BLUE}🎯 $PHILOSPHY_VIOLATIONS 个 Zig 哲学违反${NC}"
    fi

    echo ""
    echo "❌ 质量门禁未通过"
    echo ""
    echo "Zig 强调显式、手动控制、性能透明"
    echo "请确保代码符合 Zig 设计哲学后再提交"
    exit 1
fi
