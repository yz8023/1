# Requirements Document — Injector 全量修复

Feature Name: injector-full-fixes
Updated: 2026-10-09
状态: 已确认（2026-10-09 用户拍板：签名密钥两者都支持；激活码本地校验+密钥可配；公告 URL 可配置）

## Introduction

对 `com.example.injector`（Injector，APK 弹窗注入工具）做全量修复，覆盖代码审查确认的 19 项问题。核心目标：让"选包 → 找启动类 → 反编译 → 插桩 → 汇编 → 重打包 → 签名 → 预览"整条注入链路产出可安装、可运行的有效产物，并消除安全与工程缺陷。

基线环境：CodeAssist 构建，minSdk 24，targetSdk 34，Java 8 语言级。包名保持 `com.example.injector` 不变（保证已装用户可覆盖安装）。

## Glossary

- **宿主 APK**: 被注入的目标 Android 安装包。
- **弹窗包**: zip 压缩包，内含 `classes.dex`（弹窗代码）、`xymods.txt`（插桩配置，首条 `invoke-` 行为注入调用）、`assets/`（弹窗资源）。
- **插桩**: 在宿主启动类 `onCreate` 的 `invoke-super` 之后插入一条 smali 调用。
- **patched.dex**: 宿主 dex 反编译、插桩后重新汇编得到的 dex。
- **产物 APK**: 注入完成输出的 `injected.apk`。
- **AXML**: 二进制格式的 `AndroidManifest.xml`。
- **启动类**: intent-filter 命中 `MAIN` + `LAUNCHER` 的 activity 或 activity-alias 的 targetActivity。
- **激活码**: 基于 HMAC-SHA256 时间窗校验的注册码。

## Requirements

### R1 注入链路闭环（对应问题 1、9、10）

**User Story:** AS 工具使用者，我想要注入产物中的启动类真正调用弹窗代码，这样注入后的 APK 才有实际效果。

#### Acceptance Criteria

1. WHEN 宿主 dex 反编译与插桩完成，THE system SHALL 将 smali 目录汇编为 patched.dex 并写入产物 APK。
2. WHEN 汇编任一 smali 文件失败，THE system SHALL 中止注入并输出含文件路径与汇编错误详情的日志。
3. WHEN 目标类 `onCreate` 中存在 `invoke-super` 指令，THE system SHALL 在其后插入 `xymods.txt` 中首条 `invoke-` 行。
4. WHEN 插入调用执行抛出异常，THE system SHALL 捕获该异常并继续宿主原逻辑（生成的调用包裹 try/catch Throwable）。
5. IF `xymods.txt` 中不存在有效 `invoke-` 行，THE system SHALL 中止注入并提示弹窗包配置缺失。
6. WHEN 插桩完成，THE system SHALL 记录插入的完整 smali 行与目标类名到日志。

### R2 产物重打包、对齐与签名（对应问题 2、3）

**User Story:** AS 工具使用者，我想要产物 APK 能在高版本 Android 上直接安装，这样产物开箱可用。

#### Acceptance Criteria

1. THE system SHALL 保持产物 APK 中每个 entry 与原 APK 一致的压缩方式（原 STORED 条目保持 STORED）。
2. THE system SHALL 将 `resources.arsc` 以未压缩（STORED）方式写入，且数据起始偏移按 4 字节对齐。
3. THE system SHALL 在写入产物前移除原 APK `META-INF` 下的旧签名条目（`*.SF`、`*.RSA`、`*.DSA`、`*.MF`）。
4. THE system SHALL 对产物 APK 完成 v1 与 v2 双方案签名。
5. WHEN 签名密钥不存在，THE system SHALL 在 AndroidKeyStore 中生成 2048 位 RSA 密钥对并持久化，后续注入复用同一密钥（应用卸载前保持不变）。
6. WHEN 用户在设置页导入 PKCS#12（或 JKS/BKS）keystore 文件并提供密码与别名，THE system SHALL 使用该密钥对后续产物签名并持久化该选择；IF 导入校验失败，THE system SHALL 提示具体原因并保持原密钥生效。
7. WHEN 重打包或签名任一步骤失败，THE system SHALL 删除半成品产物文件并输出失败原因。

### R3 启动类解析（对应问题 4、5、6）

**User Story:** AS 工具使用者，我想要工具在各类 Manifest 结构下都找对启动类，这样注入位置准确。

#### Acceptance Criteria

1. THE system SHALL 使用纯 Java 的 AXML 解析器解析宿主 Manifest（依赖公开 SDK API 与自有解析代码）。
2. WHEN `activity-alias` 的 intent-filter 命中 `MAIN` + `LAUNCHER`，THE system SHALL 取该 alias 的 `targetActivity` 属性值作为注入目标类。
3. WHEN 类名以 `.` 开头，THE system SHALL 拼接 Manifest 的 `package` 属性生成全限定名。
4. WHEN 解析出多个启动类，THE system SHALL 弹出选择对话框；30 秒无操作后默认取列表第一项并记录日志。
5. WHEN Manifest 解析失败，THE system SHALL 输出包含根因的日志并中止注入。

### R4 预览页（对应问题 8、17）

**User Story:** AS 工具使用者，我想要预览页稳定可用，这样能在注入前验证弹窗效果。

#### Acceptance Criteria

1. THE system SHALL 将每个输入控件仅添加到父容器一次（修复 `etMethod` 重复添加导致预览页打开即崩溃）。
2. WHEN 用户点击预览，THE system SHALL 通过主线程 Handler 调用弹窗入口方法。
3. WHEN 弹窗入口方法在主线程抛出异常，THE system SHALL 在日志页展示异常信息并保证应用存活。

### R5 注册机安全模型（对应问题 12，已确认：本地校验+密钥可配）

**User Story:** AS 工具分发者，我想要激活码机制达到与部署成本匹配的防护强度。

#### Acceptance Criteria

1. THE system SHALL 从本地存储读取激活校验密钥，首次启动写入默认值，设置页提供修改入口。
2. WHEN 校验激活码，THE system SHALL 使用 HMAC-SHA256 并保留正负 10 分钟时间窗。
3. WHEN 用户未输入正确激活码，THE system SHALL 保持注入功能锁定状态。

### R6 远程公告（对应问题 15，已确认：URL 可配置）

**User Story:** AS 工具使用者，我想要看到有效的公告内容。

#### Acceptance Criteria

1. THE system SHALL 提供公告 URL 设置项并持久化到本地存储。
2. WHEN 公告请求失败，THE system SHALL 展示内置离线文案并标注"离线公告"。

### R7 安全加固（对应问题 11、13、14）

#### Acceptance Criteria

1. WHEN 解压任意 zip 前，THE system SHALL 校验每个 entry 的规范化路径位于目标目录内；IF 越界，THE system SHALL 中止解压并报错。
2. THE system SHALL 在 Manifest 中设置 `allowBackup="false"`。
3. THE system SHALL 移除 Manifest 中未使用的 `READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 权限声明。
4. THE system SHALL 移除 `largeHeap` 声明（配合 R8 流式处理）。

### R8 依赖与资源治理（对应问题 16、18）

#### Acceptance Criteria

1. THE system SHALL 将 `material` 依赖统一为单一版本（1.14.0）。
2. THE system SHALL 将 smali 全家桶统一为单一版本集（baksmali、smali、dexlib2 同版本），并清理 `deps/libraries.json` 中冗余条目。
3. THE system SHALL 以流式方式读写宿主 APK（逐 entry 处理，峰值内存与 entry 大小解耦）。
4. THE system SHALL 将反编译并行度上限设为 4 线程。

### R9 工程一致性（对应问题 19）

#### Acceptance Criteria

1. THE system SHALL 统一 UI 文案与日志中的产品命名为 Injector（包名不变）。
2. THE system SHALL 对关键流程（注入、重打包、签名）提供成功、失败两类完整日志。
3. WHEN 注入流程结束（无论成败），THE system SHALL 清理本次工作目录中的临时文件。

## 验收标准（整链路）

1. 使用工具注入任一样本宿主 APK 后，产物可通过 `apksigner verify` 校验。
2. 产物在 Android 11+ 设备可正常安装（`resources.arsc` 约束满足）。
3. 打开产物，启动类 `onCreate` 触发弹窗；弹窗调用抛异常时宿主功能正常。
4. 预览页在未选择任何文件时可正常打开。
