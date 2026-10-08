#!/system/bin/sh
# ============================================================
# HMA-OSS 配置诊断脚本 (纯只读, 不修改/删除任何文件)
# 用法: su -c sh ✅HMA诊断.sh   然后把全部输出发回来
# ============================================================

echo "===== 0. 运行环境 ====="
echo "uid: $(id -u 2>/dev/null)"
getprop ro.build.version.release 2>/dev/null | sed 's/^/Android 版本: /'
getprop ro.build.version.sdk 2>/dev/null | sed 's/^/SDK: /'

echo ""
echo "===== 1. HMA 相关包(检测双模块) ====="
pm list packages 2>/dev/null | grep -iE "hidemyapplist|hma_oss|hidemyass" || echo "(未找到)"
for p in org.frknkrc44.hma_oss com.tsng.hidemyapplist com.google.android.hmal; do
    v=$(dumpsys package "$p" 2>/dev/null | grep -m1 versionName)
    [ -n "$v" ] && echo "$p -> $v"
done

echo ""
echo "===== 2. Magisk 模块 ====="
if [ -d /data/adb/modules ]; then
    for m in /data/adb/modules/*; do
        [ -f "$m/module.prop" ] || continue
        name=$(grep -m1 '^name=' "$m/module.prop" | cut -d= -f2)
        ver=$(grep -m1 '^version=' "$m/module.prop" | cut -d= -f2)
        echo "$(basename "$m") | $name | $ver"
    done
else
    echo "(无 /data/adb/modules)"
fi

echo ""
echo "===== 3. /data/misc 配置目录 ====="
found=0
for d in /data/misc/hide_my_applist*; do
    [ -d "$d" ] || continue
    found=1
    echo "--- 目录: $d"
    ls "$d" 2>/dev/null | sed 's/^/    文件: /'
    if [ -f "$d/status.json" ]; then
        echo "    [status.json]"
        sed 's/^/      /' "$d/status.json" 2>/dev/null
    fi
    if [ -f "$d/config.json" ]; then
        echo "    [configVersion]"
        grep -o '"configVersion"[^,]*' "$d/config.json" | sed 's/^/      /'
        echo "    [disabledHooks]"
        grep -o '"disabledHooks"\s*:\s*\[[^]]*\]' "$d/config.json" | sed 's/^/      /'
        echo "    [settingsTemplates]"
        grep -o '"settingsTemplates"\s*:\s*{[^}]*}' "$d/config.json" | sed 's/^/      /'
    else
        echo "    (无 config.json)"
    fi
    echo "    [日志关键行]"
    for lf in "$d/log/runtime.log" "$d/log/old.log"; do
        if [ -f "$lf" ]; then
            echo "      -- $(basename "$lf") --"
            grep -E "Disabled hook|Config version|Data dir|Invalid hook|Failed to parse|config json" "$lf" 2>/dev/null | tail -20 | sed 's/^/        /'
        fi
    done
done
[ "$found" = "0" ] && echo "(未找到任何 hide_my_applist* 目录)"

echo ""
echo "===== 4. 旧路径 filesDir ====="
f=/data/data/org.frknkrc44.hma_oss/files/config.json
if [ -f "$f" ]; then
    grep -o '"configVersion"[^,]*' "$f" | sed 's/^/    /'
    grep -o '"disabledHooks"\s*:\s*\[[^]]*\]' "$f" | sed 's/^/    /'
else
    echo "(不存在)"
fi

echo ""
echo "===== 诊断结束: 把以上全部输出复制发回 ====="
