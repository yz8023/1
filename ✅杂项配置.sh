#!/system/bin/sh
#clear

# ============================================
# 创建存储目录
# ============================================
mkdir -p /data/adb/tricky_store
chmod 755 /data/adb/tricky_store

# ============================================
# 写入 target配置
# ============================================
TARGET_FILE="/data/adb/tricky_store/target.txt"
read -r -d '' BLACKLIST <<'EOF'
#com.reveny.nativecheck
#icu.nullptr.nativetest
EOF
BLACKLIST_REGEX=$(echo "$BLACKLIST" | sed 's/.*/^&$/' | paste -sd '|' -)
read -r -d '' FORCE_PKG <<'EOF'
com.chunqiudetector
com.eltavine.duckdetector
com.tencent.tmgp.sgame
EOF
{
echo "$FORCE_PKG" | sed 's/^/!/'
echo "com.google.android.gms"
echo "io.github.vvb2060.keyattestation"
echo "io.github.vvb2060.mahoshojo"
echo "com.android.vending"
echo "com.zhenxi.hunter"
pm list packages -3 | cut -d: -f2 | grep -vxFf <(echo "$FORCE_PKG")
} | sort -u | grep -v -E "$BLACKLIST_REGEX" > "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
echo "✅ target.txt 已生成"

# ============================================
# 写入 keybox.xml (来源: f=1 Yurikey | f=2 TrickyAddon | f=3 IntegrityBox)
# ============================================
f=1
d(){ curl -fLs --connect-timeout 10 "$1" 2>/dev/null || wget -qO- --timeout=10 "$1" 2>/dev/null; }
b(){ toybox base64 -d 2>/dev/null || base64 -d; }
x(){ toybox xxd -r -p 2>/dev/null || xxd -r -p; }
t=/data/adb/tricky_store/keybox.xml

if [ "$f" = 1 ];then
  raw=$(d https://raw.githubusercontent.com/Yurii0307/yurikey/main/key)
  [ -z "$raw" ] && raw=$(d https://ghproxy.net/https://raw.githubusercontent.com/Yurii0307/yurikey/main/key)
  c=$(echo "$raw" | b)
  s="Yurikey"
elif [ "$f" = 2 ];then
  raw=$(d https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra)
  [ -z "$raw" ] && raw=$(d https://ghproxy.net/https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra)
  c=$(echo "$raw" | grep -v '^#' | tr -d '\n\r ' | x | b)
  s="TrickyAddon"
elif [ "$f" = 3 ];then
  raw=$(d https://raw.githubusercontent.com/MeowDump/MeowDump/main/NullVoid/OptimusPrime)
  [ -z "$raw" ] && raw=$(d https://raw.gitmirror.com/MeowDump/MeowDump/main/NullVoid/OptimusPrime)
  [ -z "$raw" ] && raw=$(d https://ghproxy.net/https://raw.githubusercontent.com/MeowDump/MeowDump/main/NullVoid/OptimusPrime)
  for i in {1..10};do
    raw=$(echo "$raw" | tr -d '\n\r ' | b)
  done
  c=$(echo "$raw" | x | tr 'A-Za-z' 'N-ZA-Mn-za-m')
  s="IntegrityBox"
else
  echo "❌ 无效源"
  exit 1
fi
echo "$c" > "$t"
chmod 644 "$t"
echo "✅ Keybox 安装完成 (来源: $s)"

# ============================================
# 写入 tee_status
# ============================================
echo -n 'teeBroken=true' > /data/adb/tricky_store/tee_status
chmod 644 /data/adb/tricky_store/tee_status
echo "✅ tee_status 已写入"

# ============================================
# 写入 security_patch.txt
# ============================================
m=2
d2(){ curl --connect-timeout 10 -Ls "$1" 2>/dev/null || busybox wget -T 10 -qO- "$1" 2>/dev/null; }
g(){ s=$(d2 "https://source.android.com/docs/security/bulletin/pixel" | sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' | head -n1); test -n "$s" && echo "$s" && return 0; return 1; }
if [ "$m" = 2 ];then
  s=$(grep "^ro.build.version.security_patch=" /system/build.prop 2>/dev/null | cut -d= -f2)
  [ -z "$s" ] && s=$(getprop ro.build.version.security_patch)
  u="系统"
else
  s=$(g); u="官网"
  if [ -z "$s" ];then
    for f in /data/adb/modules/playintegrityfix/pif.json /data/adb/pif.json /data/adb/modules/playintegrityfix/pif.prop /data/adb/pif.prop /data/adb/modules/playintegrityfix/custom.pif.json /data/adb/modules/playintegrityfix/custom.pif.prop;do
      [ -f "$f" ] && { p=$f; break; }
    done
    if [ -n "$p" ];then
      if echo "$p" | grep -q prop;then
        s=$(grep SECURITY_PATCH "$p" | cut -d= -f2 | tr -d '\n')
      else
        s=$(grep '"SECURITY_PATCH"' "$p" | sed 's/.*: "//;s/".*//')
      fi
      u="PIF"
    fi
  fi
  if [ -z "$s" ];then
    s=$(grep "^ro.build.version.security_patch=" /system/build.prop 2>/dev/null | cut -d= -f2)
    [ -z "$s" ] && s=$(getprop ro.build.version.security_patch)
    u="系统"
  fi
fi
if [ -n "$s" ];then
  f=$(echo "$s" | sed 's/-//g')
  t=$(date +%Y%m%d)
  y=$(echo "$f + 10000" | bc)
  if [ "$t" -lt "$y" ];then
    o=/data/adb/tricky_store/security_patch.txt
    y2=$(echo "$s" | cut -d- -f1-2 | tr -d -)
    if [ "$m" = 2 ];then
      printf "system=$y2\nboot=$s\nvendor=prop" > "$o"
    else
      printf "system=$y2\nboot=$s\nvendor=$s" > "$o"
    fi
    chmod 644 "$o"
    echo "✅ 安全补丁已写入: $s (来源: $u)"
  else
    echo "⚠️ 安全补丁日期异常: $s"
  fi
else
  echo "❌ 未找到安全补丁信息"
fi

# ============================================
# 写入 system_app
# ============================================
cat > /data/adb/tricky_store/system_app <<'EOF'
com.google.android.gms
com.google.android.gsf
com.android.vending
com.oplus.deepthinker
com.heytap.speechassist
com.coloros.sceneservice
EOF
chmod 644 /data/adb/tricky_store/system_app
echo "✅ system_app 已写入"

# ============================================
# 配置 ZygiskNext 优化
# ============================================
zygiskd_path="/data/adb/modules/zygisksu/bin/zygiskd"
if [ -f "$zygiskd_path" ]; then
  "$zygiskd_path" enforce-denylist just_umount > /dev/null 2>&1
  "$zygiskd_path" memory-type anonymous > /dev/null 2>&1
  "$zygiskd_path" linker builtin > /dev/null 2>&1
  if [ -d "/data/adb/magisk" ]; then
    mkdir -p /data/adb/zygisksu/
    echo "1" > /data/adb/zygisksu/denylist_policy
    chmod 644 /data/adb/zygisksu/denylist_policy
  fi
  echo "✅ ZygiskNext 配置完成"
else
  echo "⚠️ ZygiskNext 未安装，跳过配置"
fi

# ============================================
# 删除杂项目录和文件
# ============================================
R=$(printf '\033[0;31m')
G=$(printf '\033[0;32m')
Y=$(printf '\033[1;33m')
X=$(printf '\033[0m')
p(){ printf "%b%s%b\n" "$1" "$2" "$X";}
[ $(id -u) -ne 0 ] && { p "$R" "请用root"; exit 1; }
p "$Y" "开始清理："
paths=(
  /storage/emulated/0/Download/advanced/
  /storage/emulated/0/Documents
  /data/system/junge/
  /data/adb/tricky_store/keybox.xml.bak
  /data/adb/tricky_store/keybox.xml.old
  /data/local/tmp/kb_auto_raw
  /data/local/tmp/kb_auto_tmp.xml
  /data/local/tmp/target_new.txt
)
for t in "${paths[@]}"; do
  if [ -d "$t" ]; then
    rm -rf "$t" && p "$G" "已删目录: $t"
  elif [ -f "$t" ]; then
    rm -f "$t" && p "$G" "已删文件: $t"
  else
    p "$Y" "跳过: $t"
  fi
done
p "$G" "完事"

# ============================================
# 过avb异常
# ============================================
if [ -x "/data/adb/magisk/resetprop" ]; then
    RP="/data/adb/magisk/resetprop"
elif [ -x "/data/adb/ksu/bin/resetprop" ]; then
    RP="/data/adb/ksu/bin/resetprop"
else
    echo "错误：未找到resetprop"
    exit 1
fi
v1=$($RP ro.boot.avb_version)
v2=$($RP ro.boot.vbmeta.avb_version)
echo "avb: $v1 | vbmeta: $v2"
if [ "$v1" != "1.2" ] || [ "$v2" != "1.2" ];then
$RP ro.boot.avb_version 1.2
$RP ro.boot.vbmeta.avb_version 1.2
nv1=$($RP ro.boot.avb_version)
nv2=$($RP ro.boot.vbmeta.avb_version)
if [ "$nv1" = "1.2" ] && [ "$nv2" = "1.2" ];then
    echo "修复成功"
else
    echo "修复失败"
fi
else
echo "属性一致无需修复"
fi

# ============================================
# 解决adb调试
# ============================================
c=0
#adb
a1=$(settings get global adb_enabled);a2=$(settings get global development_settings_enabled);a3=$(settings get global adb_wifi_enabled);a4=$(settings get global adb_authorized_devices)
[ "$a1$a2$a3$a4" != "000" ]&&{ settings put global adb_enabled 0;settings put global development_settings_enabled 0;settings put global adb_wifi_enabled 0;settings put global adb_authorized_devices "";c=$((c+1));echo "adb重置";}||echo "adb无需修复"
#usb
u1=$(getprop sys.usb.config);u2=$(getprop sys.usb.state);u3=$(getprop persist.sys.usb.config);u4=$(getprop sys.usb.adb.disabled);u5=$(getprop persist.adb.enable)
[ "$u1$u2$u3$u4$u5" != "mtpmtpmtp10" ]&&{ setprop sys.usb.config mtp 2>/dev/null;setprop sys.usb.state mtp 2>/dev/null;setprop persist.sys.usb.config mtp 2>/dev/null;setprop sys.usb.adb.disabled 1 2>/dev/null;setprop persist.adb.enable 0 2>/dev/null;c=$((c+1));echo "usb重置";}||echo "usb无需修复"
echo "修复:$c"
