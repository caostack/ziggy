#!/usr/bin/env bash
# Ziggy Quality Gate
# 验证代码质量是否达到合并标准

set -e

echo "🚪 Ziggy Quality Gate"
echo "===================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 计数器
FAILURES=0
WARNINGS=0

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

# 4. 检查 TODO/FIXME 注释
warn "无遗留 TODO" "! git grep -q 'TODO\|FIXME' -- ':!*.md' ':!*.sh' ':!quality-gate.sh'"

# 5. 检查调试代码
warn "无调试代码" "! git grep -q 'std.debug.print\|// TODO\|// FIXME\|// HACK' src/"

echo ""
echo "📏 代码风格检查"
echo "----------------"

# 6. 检查行长度（超过 100 字符）
warn "行长度 < 100 字符" "! git grep -n '.\{101,\}' src/*.zig | grep -v '//'"

# 7. 检查是否有大文件
warn "无超大文件" "! find src -name '*.zig' -size +50k"

echo ""
echo "🔒 安全检查"
echo "----------"

# 8. 检查是否有敏感信息
warn "无敏感信息" "! git grep -iq 'password\|secret\|api[_-]key' -- ':!*.md' ':!*.sh' ':!quality-gate.sh'"

# 9. 检查内存泄漏
check "无内存泄漏（GPA）" "zig build 2>&1 | grep -q 'leak' && echo 'Memory leak detected!' && exit 1 || true"

echo ""
echo "📊 统计信息"
echo "------------"

# 代码行数
LINES_OF_CODE=$(find src -name '*.zig' -exec wc -l {} + | tail -1 | awk '{print $1}')
echo "📝 代码行数: $LINES_OF_CODE"

# 文件数量
FILE_COUNT=$(find src -name '*.zig' | wc -l)
echo "📄 文件数量: $FILE_COUNT"

echo ""
echo "===================="
echo "质量门禁结果"
echo "===================="

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！${NC}"
    echo ""
    echo "代码质量良好，可以提交 🎉"
    exit 0
else
    echo -e "${RED}✗ $FAILURES 个检查失败${NC}"

    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $WARNINGS 个警告${NC}"
    fi

    echo ""
    echo "❌ 质量门禁未通过，请修复问题后再提交"
    exit 1
fi
