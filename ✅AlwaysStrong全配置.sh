#!/system/bin/sh
#clear

# ============================================
# AlwaysStrong 全配置一键脚本
# 每个功能下面 k=1 开启 / k=0 关闭
# ============================================
CONFIG_DIR=/data/adb/tricky_store
MODPATH=/data/adb/modules/tricky_store

mkdir -p "$CONFIG_DIR"; chmod 755 "$CONFIG_DIR"
[ "$(id -u)" -ne 0 ] && { echo "❌ 请用root"; exit 1; }

TO=""
if timeout -k 1 5 true >/dev/null 2>&1; then TO="timeout -k 3"
elif timeout 5 true >/dev/null 2>&1; then TO="timeout"
fi
bounded(){ _t="$1"; shift; if [ -n "$TO" ]; then $TO "$_t" "$@"; else "$@"; fi; }
BB=""
for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/modules/busybox-ndk/system/*/busybox "$(command -v busybox 2>/dev/null)"; do [ -x "$b" ] && BB="$b" && break; done
SED_I="sed -i"; [ -n "$BB" ] && SED_I="$BB sed -i"
B64D="base64 -d"; echo dGVzdA== | $B64D >/dev/null 2>&1 || { [ -n "$BB" ] && B64D="$BB base64 -d"; }
dl(){ rm -f "$1"; curl -fsSL --connect-timeout 15 --max-time 110 -o "$1" "$2" 2>/dev/null; [ -s "$1" ] || wget -q -T 20 -O "$1" "$2" 2>/dev/null; [ -s "$1" ] || [ -z "$BB" ] || "$BB" wget -q -T 20 -O "$1" "$2" 2>/dev/null; [ -s "$1" ]; }

# ============================================
# 1. target配置 (1=开启 0=关闭)
# FORCE_PKG=强制生成认证的应用
# BLACKLIST=排除出target的应用(去掉行首#生效)
# ============================================
k=1
FORCE_PKG="
com.chunqiudetector
com.eltavine.duckdetector
com.tencent.tmgp.sgame
"
BLACKLIST="
#com.reveny.nativecheck
#icu.nullptr.nativetest
"
if [ "$k" = 1 ]; then
T=$(printf '\t')
M="$CONFIG_DIR/app_keybox.map"; touch "$M"
for p in $FORCE_PKG; do grep -q "^${p}${T}" "$M" || printf '%s%s-|gen\n' "$p" "$T" >> "$M"; done
for p in $BLACKLIST; do case "$p" in \#*) ;; *) grep -q "^${p}${T}" "$M" || printf '%s%soff\n' "$p" "$T" >> "$M";; esac; done
if [ -x "$MODPATH/build_target_txt.sh" ]; then
  bounded 180 sh "$MODPATH/build_target_txt.sh" "$CONFIG_DIR/target.txt" >/dev/null 2>&1
fi
if [ ! -s "$CONFIG_DIR/target.txt" ] && pm list packages >/dev/null 2>&1; then
  A3=$(pm list packages -3 | cut -d: -f2 | grep -Fxv -e com.android.vending -e com.google.android.gms -e com.google.android.gsf)
  AL=$(pm list packages | sed 's/^package://')
  ins(){ printf '%s\n' "$AL" | grep -Fxq "$1"; }
  O="com.samsung.android.spay com.samsung.android.samsungpay.gear com.samsung.android.spaytui com.samsung.android.app.spage com.sec.android.app.samsungapps com.huawei.wallet com.huawei.android.hwpay com.miui.securitycenter com.xiaomi.market com.oneplus.opbackup com.oplus.wallet com.google.android.apps.walletnfcrel com.google.android.apps.nbu.paisa.user"
  FT="$CONFIG_DIR/.as_force"; echo "$FORCE_PKG" | sed '/^$/d' > "$FT"
  BL=$(echo "$BLACKLIST" | sed '/^$/d; s/.*/^&$/' | paste -sd '|' -)
  {
    echo '!com.android.vending'; echo '!com.google.android.gms'; echo '!com.google.android.gsf'
    echo "$FORCE_PKG" | sed '/^$/d; s/^/!/'
    for p in $O; do ins "$p" && echo "$p"; done
    echo "$A3" | grep -vxFf "$FT"
  } | sort -u | sed '/^$/d' | grep -v -E "$BL" > "$CONFIG_DIR/target.txt"
  rm -f "$FT"
fi
chmod 644 "$CONFIG_DIR/target.txt" 2>/dev/null
echo "✅ target.txt: $(awk 'NF{n++}END{print n+0}' "$CONFIG_DIR/target.txt" 2>/dev/null) 个应用"
fi

# ============================================
# 2. 远程密钥 keybox.xml (1=开启 0=关闭)
# ============================================
k=1
KB_URL="http://evoker.qzz.io/key"
if [ "$k" = 1 ]; then
rm -f "$CONFIG_DIR/custom_keybox" "$CONFIG_DIR/no_auto_keybox"
if [ -x "$MODPATH/keybox_fetch.sh" ]; then
  bounded 400 sh "$MODPATH/keybox_fetch.sh" >/dev/null 2>&1
else
  W="$CONFIG_DIR/.kb_tmp"; mkdir -p "$W"
  dl "$W/key" "$KB_URL" && $B64D < "$W/key" > "$W/kb.xml" 2>/dev/null
  [ -s "$W/kb.xml" ] && head -c 4096 "$W/kb.xml" | grep -q "Keybox" && { mv -f "$W/kb.xml" "$CONFIG_DIR/keybox.xml"; chmod 600 "$CONFIG_DIR/keybox.xml"; }
  rm -rf "$W"
fi
[ -s "$CONFIG_DIR/keybox.xml" ] && head -c 4096 "$CONFIG_DIR/keybox.xml" | grep -q "Keybox" && echo "✅ Keybox 已就绪 ($(wc -c < "$CONFIG_DIR/keybox.xml") 字节)" || echo "❌ Keybox 获取失败: $KB_URL"
fi

# ============================================
# 3. 指纹 (1=开启 0=关闭) 在线随机抓取,三级回退
# ============================================
k=1
if [ "$k" = 1 ]; then
rm -f "$CONFIG_DIR/no_auto_fp"
FP=""
if [ -f "$MODPATH/engine.sh" ]; then
  set +o standalone 2>/dev/null; unset ASH_STANDALONE 2>/dev/null
  export MODPATH CONFIG_DIR SED_I
  . "$MODPATH/engine.sh"
  [ -x "$MODPATH/pif_native_fetch.sh" ] && bounded "$ENGINE_NATIVE_TIMEOUT" sh "$MODPATH/pif_native_fetch.sh" >"$CONFIG_DIR/autopif.log" 2>&1 && FP=native
  [ -z "$FP" ] && MODPATH="$MODPATH" CONFIG_DIR="$CONFIG_DIR" SED_I="$SED_I" bounded "$ENGINE_AUTOPIF_TIMEOUT" sh -c '. "$MODPATH/engine.sh"; engine_autopif' >>"$CONFIG_DIR/autopif.log" 2>&1 && FP=pif
  if [ -z "$FP" ]; then
    I=$(cat "$CONFIG_DIR/.fp_idx" 2>/dev/null); [ "$I" = 2 ] && I=1 || I=2
    echo "$I" > "$CONFIG_DIR/.fp_idx" 2>/dev/null
    [ -s "$MODPATH/pif_fallback_$I.prop" ] && engine_install_pif "$MODPATH/pif_fallback_$I.prop" >/dev/null 2>&1 && FP=local
  fi
fi
case "$FP" in native|pif) echo "✅ 指纹已在线随机获取 ($FP)";; local) echo "✅ 指纹已写入 (本地内置)";; *) echo "⚠️ 指纹未更新 (模块缺失或全部来源失败)";; esac
fi

# ============================================
# 4. 六项spoof旗标 (1=开启 0=关闭)
# spoofProvider/spoofSignature/spoofVendingSdk 保持0
# spoofVendingFinger 留空=自动(13+=1,12及以下=0)
# ============================================
k=1
spoofBuild=1
spoofProps=1
spoofProvider=0
spoofSignature=0
spoofVendingFinger=1
spoofVendingSdk=0
if [ "$k" = 1 ]; then
[ -z "$spoofVendingFinger" ] && { spoofVendingFinger=1; s=$(getprop ro.build.version.sdk 2>/dev/null); case "$s" in ''|*[!0-9]*) ;; *) [ "$s" -le 32 ] && spoofVendingFinger=0;; esac; }
{
  grep -vE '^spoof(Build|Props|Provider|Signature|VendingFinger|VendingSdk)=' "$CONFIG_DIR/spoof.conf" 2>/dev/null
  echo "spoofBuild=$spoofBuild"; echo "spoofProps=$spoofProps"; echo "spoofProvider=$spoofProvider"
  echo "spoofSignature=$spoofSignature"; echo "spoofVendingFinger=$spoofVendingFinger"; echo "spoofVendingSdk=$spoofVendingSdk"
} > "$CONFIG_DIR/spoof.conf.new" && mv -f "$CONFIG_DIR/spoof.conf.new" "$CONFIG_DIR/spoof.conf"
chmod 644 "$CONFIG_DIR/spoof.conf"
if command -v engine_enforce_spoof >/dev/null 2>&1; then engine_enforce_spoof
else
  for f in "$MODPATH/custom.pif.prop" "$MODPATH/pif.prop" "$CONFIG_DIR/custom.pif.prop" "$CONFIG_DIR/pif.prop"; do
    [ -f "$f" ] || continue
    for kv in "spoofBuild=$spoofBuild" "spoofProps=$spoofProps" "spoofProvider=$spoofProvider" "spoofSignature=$spoofSignature" "spoofVendingFinger=$spoofVendingFinger" "spoofVendingSdk=$spoofVendingSdk"; do
      key="${kv%%=*}"; $SED_I "s|^${key}=.*|${kv}|" "$f" 2>/dev/null
      grep -qE "^${key}=" "$f" || echo "$kv" >> "$f"
    done
  done
fi
echo "✅ spoof: Build=$spoofBuild Props=$spoofProps Provider=$spoofProvider Signature=$spoofSignature VendingFinger=$spoofVendingFinger VendingSdk=$spoofVendingSdk"
fi

# ============================================
# 5. spoof security 安全补丁 (1=开启 0=关闭)
# ============================================
k=1
if [ "$k" = 1 ]; then
SP=""
for f in "$CONFIG_DIR/custom.pif.prop" "$CONFIG_DIR/pif.prop" "$MODPATH/custom.pif.prop" "$MODPATH/pif.prop"; do
  [ -s "$f" ] || continue
  v=$(grep -m1 '^SECURITY_PATCH=' "$f" | cut -d= -f2- | tr -d ' "\r')
  [ -n "$v" ] && { SP=$v; break; }
done
[ -z "$SP" ] && SP=$(getprop ro.build.version.security_patch 2>/dev/null)
R=$(echo "$SP" | tr -cd '0-9')
if [ "${#R}" -eq 8 ]; then
  D="$(echo "$R" | cut -c1-4)-$(echo "$R" | cut -c5-6)-$(echo "$R" | cut -c7-8)"
  printf 'all=%s\n' "$D" > "$CONFIG_DIR/security_patch.txt"; chmod 644 "$CONFIG_DIR/security_patch.txt"
  for f in "$MODPATH/custom.pif.prop" "$CONFIG_DIR/custom.pif.prop"; do
    [ -f "$f" ] || continue
    if grep -qE '^[#]?\*\.security_patch=' "$f" 2>/dev/null; then $SED_I "s|^[#]?\*\.security_patch=.*|*.security_patch=$D|" "$f" 2>/dev/null
    else printf '*.security_patch=%s\n' "$D" >> "$f"; fi
  done
  if command -v resetprop >/dev/null 2>&1; then
    for p in ro.build.version.security_patch ro.vendor.build.version.security_patch ro.system.build.version.security_patch; do
      c=$(resetprop "$p" 2>/dev/null); cp2=$(echo "$c" | tr -cd '0-9')
      [ -n "$c" ] || continue
      [ "${#cp2}" -eq 8 ] && [ "$cp2" -ge "$R" ] && continue
      resetprop -n "$p" "$D" 2>/dev/null
    done
  fi
  echo "✅ 安全补丁已同步: $D"
else echo "⚠️ 未找到安全补丁信息"; fi
fi

# ============================================
# 6. rom屏蔽 (1=开启 0=关闭) 禁用ROM自带PI伪装
# hide_rom_markers=1 额外隐藏lineage标记
# ============================================
k=1
if [ "$k" = 1 ]; then
rm -f "$CONFIG_DIR/no_rom_spoof_block"
: > "$CONFIG_DIR/hide_rom_markers"
if command -v resetprop >/dev/null 2>&1; then
  if [ -x "$MODPATH/rom_spoof_block.sh" ]; then
    sh "$MODPATH/rom_spoof_block.sh" && echo "✅ rom 屏蔽已生效"
  else
    g=0
    resetprop 2>/dev/null | grep -qE 'persist\.sys\.(pihooks|entryhooks|spoof|pixelprops|pp)' && g=1
    [ -n "$(resetprop ro.aospa.version 2>/dev/null)" ] && g=1
    [ -n "$(resetprop net.pixelos.version 2>/dev/null)" ] && g=1
    [ -n "$(resetprop ro.afterlife.version 2>/dev/null)" ] && g=1
    [ -f /data/system/gms_certified_props.json ] && g=1
    if [ "$g" = 1 ]; then
      pp(){ resetprop -n -p "$1" "$2" 2>/dev/null; }
      for h in persist.sys.pihooks.first_api_level persist.sys.pihooks.security_patch; do resetprop 2>/dev/null | grep -q "$h" || pp "$h" ""; done
      pp persist.sys.pihooks.disable.gms_props true
      pp persist.sys.pihooks.disable.gms_key_attestation_block true
      pp persist.sys.entryhooks_enabled false
      pp persist.sys.spoof.gms false
      pp persist.sys.pixelprops.gms false
      pp persist.sys.pixelprops.gapps false
      pp persist.sys.pixelprops.google false
      pp persist.sys.pixelprops.pi false
      pp persist.sys.pp.gms false
      pp persist.sys.pp.finsky false
      getprop 2>/dev/null | grep -E '(pihook|pixelprops)' | sed 's/^\[\(.*\)\]:.*/\1/' | while read -r prop; do [ -n "$prop" ] && resetprop -p --delete "$prop" 2>/dev/null; done
      echo "✅ rom 屏蔽已生效"
    else echo "✅ 无ROM伪装引擎, 标记已写入"; fi
  fi
else echo "⚠️ 无 resetprop, rom 屏蔽跳过"; fi
fi

# ============================================
# 7. 重启Play Integrity生效 (1=开启 0=关闭)
# ============================================
k=1
if [ "$k" = 1 ]; then
killall -9 com.google.android.gms.unstable 2>/dev/null
killall -9 com.android.vending 2>/dev/null
bounded 45 am force-stop com.android.vending >/dev/null 2>&1
echo "✅ GMS/Play商店已重启, 完事"
fi
