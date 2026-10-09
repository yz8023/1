# 需求实施计划

Feature: injector-full-fixes
依据: `requirements.md`（R1-R9）、`design.md`（组件与正确性属性）
目标工程: `abcd源码/project/`（CodeAssist 工程，Java 8，minSdk 24 / targetSdk 34）

- [ ] 1. 依赖与工程配置收敛（R8.1/R8.2、R7.2/R7.3/R7.4，设计 §9）
  - [x] 1.1 更新 `module.toml`：material 统一为 1.14.0（删除 1.12.0）；dependencies 增加 `org.smali:smali:2.5.2` 与 `com.android.tools.build:apksig:8.5.0`
  - [x] 1.2 清理 `deps/libraries.json`：移除 `org.apktool:apktool-lib:2.9.3`；核对全部 smali 相关 classes 缓存路径统一为 2.5.2；按现有条目结构新增 `com.android.tools.build:apksig:8.5.0` JAR 条目
  - [x] 1.3 下载 `apksig-8.5.0.jar` 放入 `project/.platform/caches/resolved-deps/com/android/tools/build/apksig/8.5.0/`（CodeAssist 设备端离线解析用），下载失败则记录并触发设计文档中的 v2 自实现备案
  - [x] 1.4 修改 `AndroidManifest.xml`：`allowBackup="false"`；删除 `READ_/WRITE_EXTERNAL_STORAGE`；删除 `largeHeap`
- [ ] 2. core 基础组件（设计 §Components 1/3/5）
  - [x] 2.1 新建 `core.ZipSafety`：`unzipSafe(InputStream, File)` 逐 entry 规范化路径校验，越界中止并报错（R7.1，问题 11）
  - [x] 2.2 新建 `core.AxmlParser` + `core.ManifestInfo`：纯 Java 二进制 XML 解析（string pool/resource map/tag 事件流），按资源 ID 匹配属性，`activity-alias` 取 `targetActivity`，`MAIN`+`LAUNCHER` 同 filter 才计入，`.` 前缀类名拼 `package`（R3.1-R3.5，问题 4/5/6）
  - [x] 2.3 新建 `core.AlignedZipWriter`：手工 LOCAL FILE HEADER + extra field padding + data descriptor；entry 压缩方式继承原 APK；`resources.arsc` 强制 STORED + 4 字节对齐；STORED `.so` 4096 对齐；跳过 `META-INF/*.SF|*.RSA|*.DSA|*.MF`（R2.1/R2.2/R2.3，问题 2/3/18）
  - [ ] 2.4* 编写 AlignedZipWriter 正确性属性自检代码（属性 1：entry method 与原 APK 一致；属性 2：arsc STORED 且 offset%4==0），以日志形式输出
- [ ] 3. 注入链路闭环（R1，问题 1/9/10/18）
  - [ ] 3.1 新建 `core.SmaliInjector`：baksmali 反编译（jobs 上限 4）；重写插桩逻辑（解析并 `.locals`+1、插入行包裹 try/catch Throwable、标签按方法内计数保证唯一、xymods 无 invoke 行即中止）（R1.3-R1.6，问题 9/10）
  - [ ] 3.2 `SmaliInjector` 增加汇编步骤：先解包 libraries.json 内 smali jar 核对 `Smali.assemble` 实际签名，再汇编 `smali_tmp` 产出 `patched.dex`；失败保留 smali 目录路径中止注入（R1.1/R1.2，问题 1 根除）
  - [ ] 3.3 新建 `core.ApkRepackager`：`ZipFile` 流式读取 + `AlignedZipWriter` 重写 + 追加弹窗 dex（`classesN+1.dex`）与 assets（R2.1/R2.3，问题 18）
  - [ ] 3.4 改造 `doFullInject`（MainActivity.java:282）串接 AxmlParser→SmaliInjector→ApkRepackager→ApkSignerService；删除旧 `injectCallIntoDex`/`insertInvokeInOnCreate`/`rebuildApk`/`appendDirToZip`/`parseManifest`/`attrAndroidName`（问题 1/2/4/5/6 根除）
  - [ ] 3.5 注入流程 finally 清理临时工作目录（R9.3）
  - [ ] 3.6* patched.dex 回读自检（属性 4：baksmali 回读包含插入 invoke 与 `.catch Throwable`），以日志输出
- [ ] 4. 签名服务（R2.4-R2.7，问题 2）
  - [ ] 4.1 新建 `core.ApkSignerService`：AndroidKeyStore 生成 RSA-2048 密钥（别名 `injector_autogen`，SIGNATURE 用途），持久化复用（R2.5）
  - [ ] 4.2 apksig 签名执行：`DefaultApkSignerEngine`（minSdk 24，v1+v2 开启）+ `ApkSigner.sign()`；失败删除半成品并报错（R2.4/R2.7，属性 3）
  - [ ] 4.3 keystore 导入：设置页选择 `.p12/.jks/.bks` + 密码 + 别名，按 PKCS12→JKS→BKS 顺序尝试加载，成功持久化选择、失败提示具体原因并回退自动密钥（R2.6）
- [ ] 5. 页面与交互修复（R4/R5/R6/R9，问题 7/8/11/12/15/17）
  - [ ] 5.1 预览页修复：删除 MainActivity.java:687-688 重复 addView；入口方法经 `Handler(Looper.getMainLooper())` 主线程调用，后台线程带 30 秒超时等待并回写日志（R4.1-R4.3，问题 8/17）
  - [ ] 5.2 `askUserWhichActivity`（MainActivity.java:633）增加 30 秒超时，超时取列表第一项并记日志（R3.4，问题 7）
  - [ ] 5.3 新增设置页：公告 URL、激活密钥、keystore 导入三组配置项并持久化到 SharedPreferences（R5.1/R6.1）
  - [ ] 5.4 注册机页：密钥改从 SharedPreferences 读取（与设置页同步）；`hmac()`（MainActivity.java:1055）异常上抛由页面展示（问题 12）
  - [ ] 5.5 公告页：`loadNotice` 改读配置 URL，请求失败回退离线文案并标注"离线公告"（R6.2，问题 15）
  - [ ] 5.6 `unzip()`（MainActivity.java:1083）切换至 `ZipSafety.unzipSafe`；UI 文案与 strings.xml/theme 命名 Aurora→Injector（包名保持不变）（R9.1，问题 11 收尾）
- [ ] 6. 检查点与交付
  - [ ] 6.1 检查点：静态一致性自查——导入、方法签名、调用点全部对齐，无残留对已删除方法的引用；如有疑问询问用户
  - [ ] 6.2* 回写设计文档 Risks 表（已验证/已触发项）与交付说明
  - [ ] 6.3 重新打包 `abcd源码.zip` 并提交仓库，供回传 CodeAssist 使用
