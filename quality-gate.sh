#!/usr/bin/env bash
# Ziggy Quality Gate - Honest Version
# 诚实的质量门禁：自动化检查 + 人工审查

set -e

echo "🚪 Ziggy 质量门禁"
echo "================"
echo ""
echo "⚠️  注意：自动化检查只能发现问题的一部分"
echo "   真正的质量需要人工代码审查"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILURES=0

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

warn() {
    local name="$1"
    local command="$2"

    echo -n "⚠️  $name... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ WARNING${NC}"
        return 0
    fi
}

echo "📋 自动化检查"
echo "------------"

# 1. 编译检查
check "编译通过" "zig build"

# 2. 测试检查
check "测试通过" "zig build test"

# 3. 内存泄漏检查
check "无内存泄漏" "! zig build 2>&1 | grep -q 'leak'"

echo ""
echo "🎯 Zig 风格建议（参考）"
echo "--------------------"

warn "使用 defer 清理资源" "git grep -q 'defer' src/*.zig"

warn "显式错误处理" "git grep -q 'try\|catch' src/*.zig"

warn "使用 Allocator 参数" "git grep -q 'Allocator' src/*.zig"

warn "使用 []const u8 而非指针" "git grep -q '\[\]const u8\|\[\]u8' src/*.zig"

warn "避免 std.debug.print" "! git grep -q 'std.debug.print' src/"

echo ""
echo "🧹 代码质量"
echo "----------"

warn "无大文件（<500行）" "! find src -name '*.zig' -exec wc -l {} + | awk '$1 > 500'"

warn "行长度适中（<120字符）" "! git grep -n '.\{120,\}' src/*.zig | grep -v '//' | head -5"

echo ""
echo "📊 统计信息"
echo "------------"

LINES=$(find src -name '*.zig' -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
echo "📝 代码行数: $LINES"

FILES=$(find src -name '*.zig' 2>/dev/null | wc -l)
echo "📄 文件数量: $FILES"

echo ""
echo "========================================"
echo ""
echo -e "${BLUE}ℹ️  诚实声明${NC}"
echo ""
echo "这些检查只能发现**表面问题**。"
echo "真正符合 Zig 哲学需要："
echo ""
echo "1. ✅ 人工代码审查 - PR 中逐行讨论"
echo "2. ✅ 团队共识约定 - TEAM_CONVENTIONS.md"
echo "3. ✅ 参考 Zig 标准库 - zig/std/ 是最好的示例"
echo "4. ✅ 社区讨论 - ziggit.dev, Zig Show"
echo ""
echo "🎓 推荐资源："
echo "  - Zig 标准库: https://github.com/ziglang/zig/tree/master/std"
echo "  - 社区讨论: https://ziggit.dev/"
echo "  - 风格讨论: https://ziggit.dev/t/1750"
echo ""

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✅ 自动化检查通过！${NC}"
    echo ""
    echo "但请记住：这只是基础检查"
    echo "提交 PR 时请确保代码经过人工审查"
    exit 0
else
    echo -e "${RED}❌ $FAILURES 个检查失败${NC}"
    echo ""
    echo "请修复基础问题后再提交"
    exit 1
fi
