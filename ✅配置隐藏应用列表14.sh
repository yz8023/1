#!/bin/bash
#clear
set -euo pipefail

# ===================== ANSI 颜色定义 =====================
# 低饱和柔和配色，适配深色终端
GREEN='\033[0;92m'        # 成功：淡薄荷绿
YELLOW='\033[0;93m'       # 警告：浅暖橙
RED='\033[0;91m'          # 错误：淡红
CYAN='\033[0;96m'         # 标题：淡青
MAGENTA='\033[0;95m'     # 统计标签：淡灰紫
WHITE='\033[0;97m'        # 正文：柔和白
BLUE='\033[0;94m'         # 备注：淡天蓝
DIM='\033[2m'             # 次要信息：暗色
RESET='\033[0m'

# 分割线颜色：浅灰，弱化存在感
LINE='\033[0;37m'

# ===================== 输出函数 =====================
print_color() { echo -e "${1}${2}${RESET}"; }
print_stat()  { printf "  ${MAGENTA}%-24s${RESET} ${WHITE}%s${RESET}\n" "$1" "$2"; }
print_sub()   { printf "    ${DIM}%-22s${RESET} ${DIM}%s${RESET}\n" "$1" "$2"; }
print_line()  { echo -e "${LINE}──────────────────────────────────────────${RESET}"; }

# ===================== 权限调整 =====================
print_color "$YELLOW" "[*] 调整 SELinux 权限"
setenforce 0 || { print_color "$RED" "[!] 无 Root 权限"; exit 1; }

# ===================== 配置常量 =====================
PKG="org.frknkrc44.hma_oss"

# ===================== 检测配置文件路径 =====================
print_color "$YELLOW" "[*] 检测 HMA 配置文件路径..."

# 定义所有可能的配置路径
CONFIG_PATHS=()

# 新版本路径：/data/misc/hide_my_applist*/config.json
if [ -d "/data/misc" ]; then
    while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            CONFIG_PATHS+=("$dir/config.json")
        fi
    done < <(find /data/misc -maxdepth 1 -type d -name "hide_my_applist*" 2>/dev/null)
fi

# 旧版本路径：/data/data/org.frknkrc44.hma_oss/files/config.json
CONFIG_PATHS+=("/data/data/$PKG/files/config.json")

# 显示找到的路径
for path in "${CONFIG_PATHS[@]}"; do
    if [ -d "$(dirname "$path")" ] || [ -f "$path" ]; then
        print_color "$GREEN" "[√] 找到配置路径: $path"
    else
        print_color "$DIM" "[ ] 配置路径不存在: $path"
    fi
done

am force-stop "$PKG"

# =============================================
# 全局可见列表（白名单模板里允许看到的App）
# =============================================
exclude_packages="com.alibaba.wireless
my.maya.android
com.realtech.xiaocan
com.tencent.tim
com.android.vending
com.coolapk.market
cn.cyberIdentity.certification
com.tencent.tmgp.sgamece
com.daofeng.zuhaowan
com.eg.android.AlipayGphone
com.google.android.gms
com.oplus.games
com.yiyou.ga
com.tencent.gamehelper.smoba
com.jingdong.app.mall
com.kuaishou.nebula
com.liuzh.deviceinfp
com.sankuai.meituan
com.smile.gifmaker
com.ss.android.ugc.aweme
mark.via
com.taobao.taobao
com.tmri.app.main
com.tencent.mm
com.xt.retouch
com.tencent.mobileqq
com.tencent.tmgp.pubgmhd
com.tencent.tmgp.sgame"

mapfile -t exclude_array <<< "$exclude_packages"

# =============================================
# 游戏模板里的可见列表
# =============================================
game_apps=(
com.tencent.tmgp.sgame
com.tencent.mobileqq
com.ss.android.ugc.aweme
com.tencent.mm
com.tencent.gamehelper.smoba
com.oplus.games
com.tencent.tmgp.sgamece
com.smile.gifmaker
com.xingin.xhs
com.kuaishou.nebula
)

# =============================================
# 应用额外配置
# =============================================

# 【可见】让当前应用看到以下应用
declare -A islook
islook["com.coolapk.market"]="
mark.via
com.quark.browser
com.taobao.idlefish
"

islook["com.sankuai.meituan"]="
com.baidu.BaiduMap
"

islook["anti.rusda"]="
mark.via"

islook["com.ss.android.ugc.aweme"]="
com.lemon.lv
com.xt.retouch
com.eg.android.AlipayGphone
"

islook["com.xd.xdt"]="
com.taptap
"

islook["com.chunqiunativecheck"]="
com.tencent.soter.soterserver
"


# 【不可见】让当前应用看不到以下应用
declare -A nolook
nolook["com.magicbelt.ninepatch"]="
com.canghai.haoka
"

# ===================== 统一配置区 =====================
DEFAULT_PERM='[]'
DEFAULT_EXTRA='[]'

# -------------------------------------------------------
# 禁用注入点 (HMA-OSS 设置里的"禁用注入点"/disableHooks)
# 格式: "类名|方法名|参数个数"   参数个数几乎都是 -1, 留空数组 = 全部启用
# 例子(去掉行首#生效):
#   "com.android.server.wm.ActivityStarter|startActivity|-1"
#   "com.android.server.wm.ActivityStarter|execute|-1"
#   "com.android.server.accessibility.AccessibilityManagerService|addClient|-1"
#   "com.android.server.pm.AppsFilterImpl|shouldFilterApplication|-1"
#   "com.android.server.pm.ComputerEngine|getInstallSourceInfo|-1"
# 注意: 一行格式错误会导致整个 config.json 解析失败(隐藏全部失效)
# 修改后需重启手机生效; 精确三元组以 HMA 应用内列表为准
# -------------------------------------------------------
disabled_hooks=(
"com.android.server.pm.ComputerEngine|getPackageInfoInternal|-1"
"com.android.server.pm.ComputerEngine|getApplicationInfoInternal|-1"
)

# 构建 disabledHooks JSON
build_disabled_hooks_json() {
    local out="[" first=true item cls mth cnt
    for item in "${disabled_hooks[@]}"; do
        IFS='|' read -r cls mth cnt <<< "$item"
        if [[ -z "$cls" || -z "$mth" || -z "$cnt" ]]; then
            print_color "$RED" "[!] 禁用注入点格式错误(应为 类名|方法名|参数个数): $item"
            exit 1
        fi
        $first && first=false || out+=","
        out+="{\"className\":\"$cls\",\"methodName\":\"$mth\",\"argumentCount\":$cnt}"
    done
    echo "${out}]"
}

DISABLED_HOOKS_JSON=$(build_disabled_hooks_json)

# -------------------------------------------------------
# 特殊GID权限配置
# 1015  = SDCARD_RW_GID        (禁用SD卡读写)
# 1023  = MEDIA_RW_GID         (禁用媒体文件读写)
# 1032  = PACKAGE_INFO_GID     (禁用获取应用包信息)
# 1077  = EXTERNAL_STORAGE_GID (禁用读取storage外部存储)
# 1078  = EXT_DATA_RW_GID      (禁用读取data数据目录)
# 1079  = EXT_OBB_RW_GID       (禁用读写obb数据包)
# 3003  = INET_GID             (禁用联网)
# 9997  = SHARED_USER_GID      (禁用共享用户ID)
# -------------------------------------------------------
declare -A perm_map
perm_map["luna.safe.luna"]='[1015,1023,1032,1077,1078,1079,9997]'
perm_map["chunqiu.safe.detector"]='[1015,1023,1032,1077,1078,1079,9997]'
perm_map["com.ayang.wzkjgjx"]='[3003]'
perm_map["rs.adsregex"]='[3003]'
perm_map["com.tosks.tool"]='[3003]'
perm_map["cn.tosks.tool"]='[3003]'
perm_map["com.window.hook"]='[3003]'
perm_map["com.tencent.mobileqq"]='[1032,1078,1079]'
perm_map["com.envdetector"]='[1077,1078,1079]'
perm_map["com.tgp.autologin"]='[1077,1078,1079,9997]'

# -------------------------------------------------------
# 需要隐藏【无障碍】和【开发者选项】的应用列表
# -------------------------------------------------------
need_hide_access=(
com.tencent.mm
cc.aoeiuv020.iamnotdisabled
com.eg.android.AlipayGphone
com.kuaishou.nebula
com.tencent.mobileqq
io.github.nitsuya.donottryaccessibility
com.taobao.taobao
com.eltavine.duckdetector
com.tmri.app.main
com.anycheck.app
com.envdetector
com.sankuai.meituan
com.studio.duckdetector
me.ele
)

# -------------------------------------------------------
# 黑名单应用
# -------------------------------------------------------
black=(
com.byxiaorun.detector
chunqiu.safe
com.tencent.mobileqq
com.xingin.xhs
com.anycheck.app
wu.hmal.detector
com.yiyou.ga
ph.com.bdo.retail
com.github.android
com.zhenxi.hunter
io.github.vvb2060.mahoshojo
com.taobao.taobao
io.github.huskydg.memorydetector
icu.nullptr.nativetest
com.eltavine.duckdetector
com.coloros.phonemanager
com.youhu.laifu
com.kotak.neo
com.chunqiunativecheck
anti.rusda
com.maple.detect
com.studio.duckdetector
icu.nullptr.applistdetector
com.shizi.tool.p3
chunqiu.safe.detector
com.mantle
com.versec.shield
koe.nbhb.bn
com.violet.safe
com.guangtouqiang.apk
)

# -------------------------------------------------------
# 白名单应用
# -------------------------------------------------------
white=(
com.alibaba.android.rimet
com.xhey.xcamera
com.baolei.cn
com.canghai.haoka
w2a.app7881.com
com.hicorenational.antifraud
com.tmri.app.main
com.icicibank.fastag
io.liankong.riskdetector
com.chunqiudetector
com.ascs.message.example
com.lingqing.detector
cn.soulapp.android
me.ele
com.envdetector
com.miHoYo.ys.bilibili
com.uhaozu.autoapp
com.tgp.autologin
cn.gov.tax.its
com.sdu.didi.psnger
com.miHoYo.hkrpg
com.oplus.safecenter
com.tencent.tmgp.pubgmhd
com.alibaba.wireless
com.reveny.nativecheck
com.coolapk.market
com.daofeng.zuhaowan
com.godevelopers.OprekCek
com.cimb.cimbocto
com.kuaishou.nebula
com.example.myapplication
com.smile.gifmaker
com.fantasytat.det
com.tsng.applistdetector
com.tudou.tool
com.houvven.guise
fansirsqi.xposed.sesame
com.sankuai.meituan
luna.safe.luna
)

# -------------------------------------------------------
# 游戏应用
# -------------------------------------------------------
game=(
com.tencent.tmgp.sgame
com.tencent.tmgp.sgamece
com.xd.xdt
me.garfieldhan.holmes
)

# ===================== 函数定义区 =====================

# 换行分隔转JSON数组
format_extra_list() {
    local raw="$1"
    local result=""
    
    if [[ -z "$raw" ]]; then
        echo "[]"
        return
    fi
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        result+="\"$line\","
    done <<< "$raw"
    
    echo "[${result%,}]"
}

get_extra_visible() {
    format_extra_list "${islook[$1]-}"
}

get_extra_hidden() {
    format_extra_list "${nolook[$1]-}"
}

is_in_hide_access() {
    local target="$1"
    for item in "${need_hide_access[@]}"; do
        [[ "$item" == "$target" ]] && return 0
    done
    return 1
}

has_special_perm() {
    local target="$1"
    [[ -n "${perm_map[$target]+_}" ]] && return 0 || return 1
}

gen_entry() {
    local p="$1"
    local use_white="$2"
    local exclude_sys="$3"
    local template="$4"

    local perm="${perm_map[$p]-$DEFAULT_PERM}"
    local extra=$(get_extra_visible "$p")
    local extra_opposite=$(get_extra_hidden "$p")

    if is_in_hide_access "$p"; then
        local settings='["accessibility","dev_options"]'
    else
        local settings='[]'
    fi

    echo "\"$p\":{
        \"useWhitelist\": $use_white,
        \"excludeSystemApps\": $exclude_sys,
        \"hideInstallationSource\": false,
        \"hideSystemInstallationSource\": false,
        \"excludeTargetInstallationSource\": false,
        \"invertActivityLaunchProtection\": false,
        \"excludeVoldIsolation\": false,
        \"restrictedZygotePermissions\": $perm,
        \"applyTemplates\": [\"$template\"],
        \"applyPresets\": [],
        \"applySettingTemplates\": [],
        \"applySettingsPresets\": $settings,
        \"extraAppList\": $extra,
        \"extraOppositeAppList\": $extra_opposite
    }"
}

gen_empty_access_entry() {
    local p="$1"
    local perm="${perm_map[$p]-$DEFAULT_PERM}"
    local extra=$(get_extra_visible "$p")
    local extra_opposite=$(get_extra_hidden "$p")

    echo "\"$p\":{
        \"useWhitelist\": false,
        \"excludeSystemApps\": false,
        \"hideInstallationSource\": false,
        \"hideSystemInstallationSource\": false,
        \"excludeTargetInstallationSource\": false,
        \"invertActivityLaunchProtection\": false,
        \"excludeVoldIsolation\": false,
        \"restrictedZygotePermissions\": $perm,
        \"applyTemplates\": [],
        \"applyPresets\": [],
        \"applySettingTemplates\": [],
        \"applySettingsPresets\": [\"accessibility\",\"dev_options\"],
        \"extraAppList\": $extra,
        \"extraOppositeAppList\": $extra_opposite
    }"
}

add_entry() {
    local p="$1"
    local use_white="$2"
    local exclude_sys="$3"
    local template="$4"

    if [[ " ${processed[@]} " =~ " $p " ]]; then
        # 应用已存在，需要更新
        duplicates_total=$((duplicates_total + 1))
        
        # 找到并删除旧条目
        for i in "${!all[@]}"; do
            if [[ "${all[$i]}" =~ "\"$p\":" ]]; then
                unset "all[$i]"
                break
            fi
        done
        
        # 添加新条目
        all+=("$(gen_entry "$p" "$use_white" "$exclude_sys" "$template")")
        processed_template["$p"]="$template"
    else
        # 新应用
        all+=("$(gen_entry "$p" "$use_white" "$exclude_sys" "$template")")
        processed+=("$p")
        processed_template["$p"]="$template"
    fi
}

# ===================== 配置自校验函数 =====================

# 检查数组内重复元素
check_duplicates_in_array() {
    local array_name="$1"
    shift
    local arr=("$@")
    local seen=()
    local dup_found=false
    
    for item in "${arr[@]}"; do
        if [[ " ${seen[@]} " =~ " $item " ]]; then
            if ! $dup_found; then
                print_color "$RED" "[!] $array_name 列表中存在重复定义"
                dup_found=true
            fi
            print_color "$RED" "  -> $item (重复)"
        else
            seen+=("$item")
        fi
    done
}

# 主校验函数（仅检查异常冲突）
validate_configuration() {
    local has_issues=false
    
    echo ""
    print_line
    print_color "$CYAN" "[*] 配置自校验"
    echo ""
    
    # ==== 检查1：黑名单与白名单/游戏的严重冲突 ====
    local conflict_found=false
    for p in "${black[@]}"; do
        if [[ " ${white[@]} " =~ " $p " ]]; then
            if ! $conflict_found; then
                print_color "$RED" "[!] 严重冲突：应用同时存在于黑名单和白名单"
                conflict_found=true
                has_issues=true
            fi
            print_color "$RED" "  -> $p [黑名单 ∩ 白名单]"
        fi
        if [[ " ${game[@]} " =~ " $p " ]]; then
            if ! $conflict_found; then
                print_color "$RED" "[!] 严重冲突：应用同时存在于黑名单和游戏列表"
                conflict_found=true
                has_issues=true
            fi
            print_color "$RED" "  -> $p [黑名单 ∩ 游戏]"
        fi
    done
    
    # ==== 检查2：各类别内部重复检查（仅显示有问题的） ====
    check_duplicates_in_array "黑名单" "${black[@]}"
    check_duplicates_in_array "白名单" "${white[@]}"
    check_duplicates_in_array "游戏" "${game[@]}"
    check_duplicates_in_array "无障碍隐藏" "${need_hide_access[@]}"
    
    # ==== 汇总结果 ====
    if ! $has_issues && ! $conflict_found; then
        print_color "$GREEN" "[√] 配置自校验通过，无异常冲突"
    else
        print_color "$YELLOW" "[!] 发现配置冲突，已自动处理（后定义的覆盖先定义的）"
    fi
    print_line
}

# ===================== 智能启动函数 =====================
smart_launch_hma() {
    local pkg="$1"
    local launched=false
    
    # 获取 HMA 的主 Activity
    local hma_activity=""
    
    # 方法1：使用 cmd package resolve-activity（Android 10+）
    hma_activity=$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -n 1)
    if [ -n "$hma_activity" ] && [ "$hma_activity" != "$pkg" ]; then
        :
    else
        # 方法2：从 pm dump 中解析
        hma_activity=$(pm dump "$pkg" 2>/dev/null | \
            grep -A 5 "android.intent.action.MAIN" | \
            grep -oE "$pkg/[a-zA-Z0-9_.$]+" | \
            head -n 1)
    fi
    
    # 方法3：使用默认 Activity
    if [ -z "$hma_activity" ]; then
        hma_activity="$pkg/.MainActivityLauncher"
    fi
    
    # 尝试启动（按优先级）
    local attempts=(
        # Android 16 / MT管理器：完整路径
        "/system/bin/am start -n '$hma_activity'"
        # Android 16 / MT管理器：cd 根目录
        "cd / && am start -n '$hma_activity'"
        # 通用：sh -c 包装
        "sh -c 'am start -n \"$hma_activity\"'"
        # Android 10+：cmd activity
        "cmd activity start-activity -n '$hma_activity'"
        # 通用：am start 包名
        "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p '$pkg'"
        # 通用：am start 完整
        "am start -n '$hma_activity'"
        # 旧版本：monkey
        "monkey -p '$pkg' -c android.intent.category.LAUNCHER 1"
        # 备用：nohup 后台
        "nohup am start -n '$hma_activity' >/dev/null 2>&1 & sleep 2"
    )
    
    for cmd in "${attempts[@]}"; do
        if eval "$cmd" >/dev/null 2>&1; then
            sleep 1
            # 检查是否真的启动了
            if pidof "$pkg" >/dev/null 2>&1; then
                launched=true
                break
            fi
        fi
    done
    
    if $launched; then
        return 0
    else
        return 1
    fi
}

# ===================== 主处理逻辑 =====================

all=()
processed=()
duplicates_by_pkg=()
declare -A processed_template

black_count=0
white_count=0
game_count=0
access_only_count=0
perm_count=0
duplicates_total=0

print_color "$CYAN" "[*] 正在生成应用配置..."

# 1. 黑名单
for p in "${black[@]}"; do
    add_entry "$p" false false "黑名单"
done

# 2. 白名单
for p in "${white[@]}"; do
    add_entry "$p" true true "白名单"
done

# 3. 游戏
for p in "${game[@]}"; do
    add_entry "$p" true true "游戏"
done

# 4. 补全无障碍隐藏
for p in "${need_hide_access[@]}"; do
    if [[ ! " ${processed[@]} " =~ " $p " ]]; then
        all+=("$(gen_empty_access_entry "$p")")
        processed+=("$p")
        processed_template["$p"]="无模板（仅隐藏无障碍）"
        access_only_count=$((access_only_count + 1))
    else
        duplicates_total=$((duplicates_total + 1))
        for i in "${!all[@]}"; do
            if [[ "${all[$i]}" =~ "\"$p\":" ]]; then
                if [[ " ${black[@]} " =~ " $p " ]]; then
                    all[$i]="$(gen_entry "$p" false false "黑名单")"
                    duplicates_by_pkg+=("$p: 黑名单 + 无障碍隐藏")
                elif [[ " ${white[@]} " =~ " $p " ]]; then
                    all[$i]="$(gen_entry "$p" true true "白名单")"
                    duplicates_by_pkg+=("$p: 白名单 + 无障碍隐藏")
                elif [[ " ${game[@]} " =~ " $p " ]]; then
                    all[$i]="$(gen_entry "$p" true true "游戏")"
                    duplicates_by_pkg+=("$p: 游戏 + 无障碍隐藏")
                fi
                break
            fi
        done
    fi
done

# ==========【修复】拼接 scope 变量，解决 unbound variable ==========
scope=$(IFS=, ; echo "${all[*]}")

# 重新统计模板分布（去重后的准确计数）
black_count=0
white_count=0
game_count=0

for p in "${processed[@]}"; do
    template="${processed_template[$p]}"
    case "$template" in
        "黑名单") black_count=$((black_count + 1)) ;;
        "白名单") white_count=$((white_count + 1)) ;;
        "游戏")   game_count=$((game_count + 1)) ;;
    esac
done

# 统计特殊权限
for p in "${processed[@]}"; do
    has_special_perm "$p" && perm_count=$((perm_count + 1))
done

hide_access_total=$((access_only_count + duplicates_total))

# ===================== 合并提示（仅显示数量） =====================

if [[ ${#duplicates_by_pkg[@]} -gt 0 ]]; then
    print_color "$DIM" "[*] 模板与无障碍隐藏合并：${#duplicates_by_pkg[@]} 个应用（正常处理）"
fi

# ===================== 【修复】读取三方包，解决管道丢失包名BUG =====================
raw_all=$(pm list packages -3 2>/dev/null)
pkg_clean=$(echo "$raw_all" | sed 's/package://')
# 过滤exclude_packages
pkg_filtered=$(echo "$pkg_clean" | grep -vFf <(echo "$exclude_packages"))
app_list=$(echo "$pkg_filtered" | awk '{print "\""$0"\""}' | tr '\n' ',' | sed 's/,$//')

# ===================== 白名单、游戏模板列表 =====================
whitelist_packages=$(printf '"%s",' "${exclude_array[@]}" | sed 's/,$//')
game_list=$(printf '"%s",' "${game_apps[@]}" | sed 's/,$//')

# 追加虚拟包 com.ss.android.ugc.aweme.yyds 到黑名单模板
if [[ -n "$app_list" ]]; then
    app_list="$app_list,\"com.ss.android.ugc.aweme.yyds\""
else
    app_list="\"com.ss.android.ugc.aweme.yyds\""
fi

if [ -z "$app_list" ]; then
    print_color "$RED" "[!] 没有检测到第三方应用"
    setenforce 1
    exit 1
fi

blacklist_app_count=$(echo "$pkg_filtered" | wc -l)

# ===================== 写入配置文件（同时覆盖新旧路径） =====================

# 生成配置内容
CONFIG_CONTENT=$(cat <<EOF
{
    "configVersion": 90,
    "detailLog": false,
    "maxLogSize": 512,
    "forceMountData": true,
    "altAppDataIsolation":true,
    "templates": {
        "黑名单": { "isWhitelist": false, "appList": [ $app_list ] },
        "白名单": { "isWhitelist": true, "appList": [ $whitelist_packages ] },
        "游戏": { "isWhitelist": true, "appList": [ $game_list ] }
    },
    "settingsTemplates": {},
    "disabledHooks": $DISABLED_HOOKS_JSON,
    "scope": { $scope }
}
EOF
)

# 写入所有可能的配置路径
written_count=0
for path in "${CONFIG_PATHS[@]}"; do
    CONFIG_DIR=$(dirname "$path")
    
    # 创建目录（如果不存在）
    mkdir -p "$CONFIG_DIR" 2>/dev/null || continue
    
    # 写入配置文件
    if echo "$CONFIG_CONTENT" > "$path" 2>/dev/null; then
        # 设置正确的权限
        chmod 644 "$path" 2>/dev/null || true
        chown system:system "$path" 2>/dev/null || true
        
        written_count=$((written_count + 1))
        print_color "$GREEN" "[√] 已写入: $path"
    else
        print_color "$YELLOW" "[!] 写入失败: $path"
    fi
done

if [ $written_count -eq 0 ]; then
    print_color "$RED" "[!] 所有配置路径写入失败！"
    setenforce 1
    exit 1
fi

print_color "$GREEN" "[√] 成功写入 $written_count 个配置文件"

# ===================== 执行自校验 =====================

validate_configuration

# ===================== 恢复SELinux并启动HMA =====================
setenforce 1

print_color "$DIM" "[*] 正在启动 HMA..."

# 使用智能启动函数
if smart_launch_hma "$PKG"; then
    print_color "$GREEN" "[√] HMA 启动成功"
else
    print_color "$YELLOW" "[!] 自动启动失败，请手动打开 HMA"
fi

# 延迟一下，确保启动命令执行完毕
sleep 1

# ===================== 完成提示 =====================
echo ""
print_color "$CYAN"  "[OK] 配置生成完成"
print_line
print_color "$WHITE" "  模板分布"
print_stat  "黑名单"  "$black_count 个应用"
print_stat  "白名单"  "$white_count 个应用"
print_stat  "游戏"    "$game_count 个应用"
echo ""
print_color "$WHITE" "  防护功能"
print_stat  "无障碍+开发者隐藏"  "$hide_access_total 个应用"
print_sub   "独立配置"          "$access_only_count 个（无模板）"
print_sub   "合并配置"          "$duplicates_total 个（模板 + 隐藏）"
print_stat  "特殊GID权限限制"   "$perm_count 个应用"
print_stat  "禁用注入点"       "${#disabled_hooks[@]} 个"
echo ""
print_color "$WHITE" "  模板规模"
print_stat  "黑名单排除"  "$blacklist_app_count 个第三方应用"
print_stat  "白名单可见"  "${#exclude_array[@]} 个应用"
print_stat  "游戏可见"    "${#game_apps[@]} 个应用"
print_line
print_color "$DIM"   "  已写入 $written_count 个配置文件"
print_line
echo ""
