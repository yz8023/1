#!/system/bin/sh
# ============================================================
# HMA 诊断第2步: 时间线 + 原始日志 (纯只读)
# 用法: su -c sh ✅HMA诊断2.sh   把全部输出发回
# ============================================================

DIR=""
for d in /data/misc/hide_my_applist*; do
    [ -d "$d" ] && DIR="$d" && break
done
if [ -z "$DIR" ]; then
    echo "未找到配置目录"
    exit 0
fi
echo "配置目录: $DIR"

echo ""
echo "===== A. 关键时间线 (文件修改时间) ====="
date 2>/dev/null
uptime 2>/dev/null
echo "(status.json / maps 晚于 config.json = 守护进程在写入后启动, 禁用应已生效)"
for f in "$DIR/config.json" "$DIR/status.json" "$DIR/maps_module_thread.txt" "$DIR/log/runtime.log" "$DIR/log/old.log"; do
    if [ -e "$f" ]; then
        t=$(stat -c '%y' "$f" 2>/dev/null)
        [ -z "$t" ] && t=$(ls -ld "$f" 2>/dev/null | awk '{print $6, $7, $8}')
        echo "$t  <-  $(basename "$f")"
    fi
done

echo ""
echo "===== B. 日志文件大小 ====="
wc -c "$DIR"/log/*.log 2>/dev/null || echo "(无日志文件)"

echo ""
echo "===== C. runtime.log 末尾 30 行 (本次开机) ====="
tail -30 "$DIR/log/runtime.log" 2>/dev/null

echo ""
echo "===== D. old.log 末尾 20 行 (上次开机) ====="
tail -20 "$DIR/log/old.log" 2>/dev/null

echo ""
echo "===== E. 全日志关键行搜索 ====="
grep -hE "Disabled hook|Hooks installed|Data dir|Config version|Failed to parse|Conflicting" "$DIR"/log/*.log 2>/dev/null | tail -30 || echo "(无匹配行)"
echo "===== 诊断结束 ====="
