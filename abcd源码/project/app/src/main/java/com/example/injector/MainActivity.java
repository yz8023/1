package com.example.injector;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.XmlResourceParser;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.StyleSpan;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.AccelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.widget.NestedScrollView;

import com.google.android.material.bottomnavigation.BottomNavigationView;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.progressindicator.LinearProgressIndicator;
import com.google.android.material.radiobutton.MaterialRadioButton;
import com.google.android.material.snackbar.Snackbar;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Enumeration;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import dalvik.system.DexClassLoader;

public class MainActivity extends AppCompatActivity {

    private static final String DEFAULT_SECRET = "Aurora_Pro_#9981_Secret";
    private static final String PREF = "aurora_injector";
    private static final String KEY_SECRET = "secret_key";
    private static final String NOTICE_URL = "https://example.com/aurora_notice.txt";
    private static final long WINDOW_MS = 10 * 60_000L;

    private SharedPreferences sp;
    private FrameLayout content;
    private FloatingActionButton fab;
    private BottomNavigationView bottomNav;

    private Uri apkUri, zipUri;
    private ActivityResultLauncher<Intent> apkPicker, zipPicker;

    // 当前页面独立日志器
    private LogConsole logger;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        sp = getSharedPreferences(PREF, Context.MODE_PRIVATE);
        content = findViewById(R.id.content_container);
        fab = findViewById(R.id.fab);
        bottomNav = findViewById(R.id.bottom_nav);

        bottomNav.getMenu().clear();
        bottomNav.getMenu().add(0, 1, 0, "注入").setIcon(android.R.drawable.ic_menu_upload);
        bottomNav.getMenu().add(0, 2, 1, "预览").setIcon(android.R.drawable.ic_menu_view);
        bottomNav.getMenu().add(0, 3, 2, "注册机").setIcon(android.R.drawable.ic_menu_edit);
        bottomNav.getMenu().add(0, 4, 3, "公告").setIcon(android.R.drawable.ic_menu_info_details);

        bottomNav.setOnItemSelectedListener(item -> {
            animateBottomIcon();
            switch (item.getItemId()) {
                case 1: showInjectPage(); return true;
                case 2: showPreviewPage(); return true;
                case 3: showRegisterPage(); return true;
                case 4: showNoticePage(); return true;
            }
            return false;
        });

        fab.setOnClickListener(v -> {
            fab.animate()
                    .rotationBy(360f)
                    .scaleX(1.15f).scaleY(1.15f)
                    .setDuration(260)
                    .setInterpolator(new OvershootInterpolator(2.2f))
                    .withEndAction(() -> fab.animate()
                            .scaleX(1f).scaleY(1f)
                            .setDuration(200)
                            .start())
                    .start();
            Snackbar.make(v, R.string.fab_clicked, Snackbar.LENGTH_SHORT).show();
        });

        apkPicker = registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(), r -> {
                    if (r.getResultCode() == Activity.RESULT_OK && r.getData() != null) {
                        apkUri = r.getData().getData();
                        if (logger != null) logger.ok("已选择 APK：" + shortUri(apkUri));
                        snack("已选择 APK");
                    }
                });
        zipPicker = registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(), r -> {
                    if (r.getResultCode() == Activity.RESULT_OK && r.getData() != null) {
                        zipUri = r.getData().getData();
                        if (logger != null) logger.ok("已选择弹窗包：" + shortUri(zipUri));
                        snack("已选择弹窗包");
                    }
                });

        bottomNav.setSelectedItemId(1);
    }

    // =========================================================
    //                          注入页
    // =========================================================
    private void showInjectPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(colorAttr(com.google.android.material.R.attr.colorSurface));
        scroll.setFillViewport(true);

        LinearLayout root = column();
        scroll.addView(root, lpMatchWrap());
        content.removeAllViews();
        content.addView(scroll, lpMatchMatch());

        // 标题区
        LinearLayout header = columnNoPad();
        header.addView(h1("APK 注入器"));
        header.addView(sub("选择 APK 与弹窗包，自动解析启动类，注入调用"));
        root.addView(header);

        // 目标 APK 卡片
        MaterialCardView cardApk = mdCardOutlined();
        LinearLayout innerApk = columnNoPad();
        innerApk.setPadding(dp(20), dp(16), dp(20), dp(16));
        cardApk.addView(innerApk);
        TextInputLayout tilApk = new TextInputLayout(this);
        tilApk.setHint("目标 APK");
        TextInputEditText etApk = new TextInputEditText(this);
        etApk.setFocusable(false);
        etApk.setClickable(true);
        etApk.setOnClickListener(v -> { pressAnim(v); pickApk(); });
        tilApk.addView(etApk);
        innerApk.addView(tilApk);
        root.addView(cardApk);

        // 弹窗包卡片
        MaterialCardView cardZip = mdCardOutlined();
        LinearLayout innerZip = columnNoPad();
        innerZip.setPadding(dp(20), dp(16), dp(20), dp(16));
        cardZip.addView(innerZip);
        TextInputLayout tilZip = new TextInputLayout(this);
        tilZip.setHint("弹窗包 (classes.dex + xymods.txt + assets)");
        TextInputEditText etZip = new TextInputEditText(this);
        etZip.setFocusable(false);
        etZip.setClickable(true);
        etZip.setOnClickListener(v -> { pressAnim(v); pickZip(); });
        tilZip.addView(etZip);
        innerZip.addView(tilZip);
        root.addView(cardZip);

        // 注入模式卡片
        MaterialCardView cardMode = mdCardOutlined();
        LinearLayout innerMode = columnNoPad();
        innerMode.setPadding(dp(20), dp(16), dp(20), dp(12));
        cardMode.addView(innerMode);
        innerMode.addView(labelInline("注入模式"));
        LinearLayout modeRow = new LinearLayout(this);
        modeRow.setOrientation(LinearLayout.HORIZONTAL);
        String[] modes = {"智能", "smali", "provider", "activity"};
        final String[] chosen = {"智能"};
        for (int i = 0; i < modes.length; i++) {
            MaterialRadioButton rb = new MaterialRadioButton(this);
            rb.setText(modes[i]);
            if (i == 0) rb.setChecked(true);
            final String m = modes[i];
            rb.setOnClickListener(v -> {
                chosen[0] = m;
                rb.animate().scaleX(1.08f).scaleY(1.08f).setDuration(120)
                        .withEndAction(() -> rb.animate().scaleX(1f).scaleY(1f)
                                .setDuration(120).start()).start();
                if (logger != null) logger.info("切换注入模式：" + m);
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            modeRow.addView(rb, lp);
        }
        innerMode.addView(modeRow);
        root.addView(cardMode);

        // 进度卡片
        MaterialCardView cardProgress = mdCardOutlined();
        LinearLayout innerProg = columnNoPad();
        innerProg.setPadding(dp(20), dp(16), dp(20), dp(16));
        cardProgress.addView(innerProg);

        LinearProgressIndicator progress = new LinearProgressIndicator(this);
        progress.setMax(100);
        progress.setProgress(0);
        innerProg.addView(progress);

        TextView tvStage = new TextView(this);
        tvStage.setTextSize(12);
        tvStage.setTextColor(colorAttr(com.google.android.material.R.attr.colorOnSurfaceVariant));
        tvStage.setPadding(0, dp(10), 0, 0);
        tvStage.setText("就绪 · 0%");
        innerProg.addView(tvStage);

        MaterialButton btnStart = mdButtonFilled("开始注入");
        LinearLayout.LayoutParams blp = lpMatchWrap();
        blp.topMargin = dp(12);
        innerProg.addView(btnStart, blp);
        root.addView(cardProgress);

        // 日志面板
        logger = new LogConsole(this);
        LinearLayout.LayoutParams llp = lpMatchWrap();
        llp.topMargin = dp(8);
        root.addView(logger.view(), llp);

        logger.info("注入器就绪 · 等待选择文件");

        btnStart.setOnClickListener(v -> {
            pressAnim(v);
            if (apkUri == null || zipUri == null) {
                logger.warn("请先选择 APK 和弹窗包");
                snack("请先选择 APK 和弹窗包");
                return;
            }
            logger.clear();
            logger.info("开始注入任务 · 模式：" + chosen[0]);
            doFullInject(apkUri, zipUri, chosen[0], progress, tvStage);
        });

        animateInStagger(root);
    }

    private void doFullInject(Uri apkSrc, Uri zipSrc, String mode,
                              LinearProgressIndicator progress, TextView stage) {
        new Thread(() -> {
            long t0 = System.currentTimeMillis();
            try {
                File work = new File(getFilesDir(), "inject_work");
                delete(work);
                work.mkdirs();

                updateUi(progress, stage, 5, "复制 APK");
                logger.info("复制 APK 到工作目录…");
                File apkCopy = new File(work, "base.apk");
                try (InputStream in = getContentResolver().openInputStream(apkSrc);
                     FileOutputStream out = new FileOutputStream(apkCopy)) {
                    if (in == null) throw new IllegalStateException("无法读取 APK");
                    byte[] buf = new byte[8192]; int n; long total = 0;
                    while ((n = in.read(buf)) > 0) { out.write(buf, 0, n); total += n; }
                    logger.ok("APK 复制完成 · " + (total / 1024) + " KB");
                }

                updateUi(progress, stage, 15, "解析 AndroidManifest");
                logger.info("解析 AndroidManifest.xml…");
                List<String> launchers = parseManifest(apkCopy);
                if (launchers.isEmpty()) throw new IllegalStateException("没找到启动器 Activity");
                logger.ok("找到 " + launchers.size() + " 个启动类");
                for (String s : launchers) logger.info("  · " + s);

                updateUi(progress, stage, 25, "等待用户选择");
                final String selectedActivity = askUserWhichActivity(launchers);
                if (selectedActivity == null) {
                    logger.warn("用户取消选择");
                    runOnUiThread(() -> stage.setText("已取消"));
                    return;
                }
                logger.ok("已选择启动类：" + selectedActivity);

                updateUi(progress, stage, 35, "解包弹窗包");
                logger.info("解包弹窗包…");
                File popupDir = new File(work, "popup");
                popupDir.mkdirs();
                unzip(zipSrc, popupDir);

                File popupDex = new File(popupDir, "classes.dex");
                File configFile = new File(popupDir, "xymods.txt");
                File popupAssets = new File(popupDir, "assets");
                if (!popupDex.exists()) throw new IllegalStateException("弹窗包缺少 classes.dex");
                if (!configFile.exists()) throw new IllegalStateException("弹窗包缺少 xymods.txt");
                String config = readText(configFile);
                logger.ok("弹窗包解包完成 · dex "
                        + (popupDex.length() / 1024) + " KB");

                updateUi(progress, stage, 45, "解析调用代码");
                String smaliCall = parseSmaliCall(config);
                if (smaliCall == null || smaliCall.isEmpty()) {
                    throw new IllegalStateException("xymods.txt 里没有 smali 调用代码");
                }
                logger.info("调用代码：" + smaliCall);

                updateUi(progress, stage, 55, "定位启动类所在 dex");
                logger.info("扫描 dex 查找目标类…");
                File targetDex = findDexContainingClass(apkCopy, selectedActivity, work);
                if (targetDex == null) {
                    throw new IllegalStateException("找不到 " + selectedActivity + " 所在的 dex");
                }
                String dexEntryName = targetDex.getName();
                logger.ok("目标 dex：" + dexEntryName);

                updateUi(progress, stage, 70, "反编译并插入 smali 调用");
                File patchedDex = injectCallIntoDex(targetDex, selectedActivity, smaliCall, work);
                logger.ok("smali 插入完成");

                updateUi(progress, stage, 88, "重建 APK");
                int maxDex = findMaxDexIndex(apkCopy);
                String newPopupDexName = "classes" + (maxDex + 1) + ".dex";
                logger.info("新弹窗 dex 名称：" + newPopupDexName);

                File outApk = new File(work, "injected.apk");
                rebuildApk(apkCopy, patchedDex, dexEntryName,
                        popupDex, newPopupDexName,
                        popupAssets, outApk);

                long cost = System.currentTimeMillis() - t0;
                updateUi(progress, stage, 100, "完成：" + outApk.getAbsolutePath());
                logger.ok("注入完成 · 耗时 " + cost + " ms");
                logger.ok("输出：" + outApk.getAbsolutePath());
                runOnUiThread(() -> snack("注入完成：" + outApk.getAbsolutePath()));

            } catch (Exception e) {
                String msg = e.getMessage() == null ? e.toString() : e.getMessage();
                logger.error("注入失败：" + msg);
                runOnUiThread(() -> {
                    stage.setText("失败：" + msg);
                    snack("失败：" + msg);
                });
            }
        }).start();
    }

    private List<String> parseManifest(File apk) throws Exception {
        List<String> result = new ArrayList<>();

        File tmp = new File(getCacheDir(), "AndroidManifest.xml");
        try (ZipFile zf = new ZipFile(apk)) {
            ZipEntry e = zf.getEntry("AndroidManifest.xml");
            if (e == null) return result;
            try (InputStream in = zf.getInputStream(e);
                 FileOutputStream out = new FileOutputStream(tmp)) {
                byte[] buf = new byte[8192]; int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
        }

        byte[] axml;
        try (InputStream in = new FileInputStream(tmp)) {
            axml = readAllBytes(in);
        }

        XmlResourceParser parser;
        try {
            Class<?> xmlBlockClass = Class.forName("android.content.res.XmlBlock");
            java.lang.reflect.Constructor<?> ctor = xmlBlockClass.getConstructor(byte[].class);
            Object xmlBlock = ctor.newInstance((Object) axml);
            java.lang.reflect.Method newParser = xmlBlockClass.getMethod("newParser");
            parser = (XmlResourceParser) newParser.invoke(xmlBlock);
        } catch (Throwable t) {
            throw new IllegalStateException("解析 AndroidManifest 失败：" + t);
        }

        String pkg = null;
        String current = null;
        boolean sawMain = false;

        int event;
        while ((event = parser.next()) != XmlResourceParser.END_DOCUMENT) {
            if (event == XmlResourceParser.START_TAG) {
                String name = parser.getName();
                if ("manifest".equals(name)) {
                    for (int i = 0; i < parser.getAttributeCount(); i++) {
                        if ("package".equals(parser.getAttributeName(i))) {
                            pkg = parser.getAttributeValue(i);
                            break;
                        }
                    }
                } else if ("activity".equals(name) || "activity-alias".equals(name)) {
                    current = attrAndroidName(parser);
                    sawMain = false;
                } else if ("action".equals(name)) {
                    String act = attrAndroidName(parser);
                    if ("android.intent.action.MAIN".equals(act)) sawMain = true;
                } else if ("category".equals(name)) {
                    String cat = attrAndroidName(parser);
                    if ("android.intent.category.LAUNCHER".equals(cat)
                            && sawMain && current != null) {
                        String full = current.startsWith(".")
                                ? (pkg == null ? "" : pkg) + current
                                : current;
                        if (!result.contains(full)) result.add(full);
                    }
                }
            } else if (event == XmlResourceParser.END_TAG) {
                String name = parser.getName();
                if ("activity".equals(name) || "activity-alias".equals(name)) {
                    current = null;
                    sawMain = false;
                }
            }
        }
        parser.close();
        return result;
    }

    private String attrAndroidName(XmlResourceParser parser) {
        for (int i = 0; i < parser.getAttributeCount(); i++) {
            String ns = parser.getAttributeNamespace(i);
            String name = parser.getAttributeName(i);
            if ("http://schemas.android.com/apk/res/android".equals(ns)
                    && "name".equals(name)) {
                return parser.getAttributeValue(i);
            }
            if ("name".equals(name) && (ns == null || ns.isEmpty())) {
                return parser.getAttributeValue(i);
            }
        }
        return null;
    }

    private File findDexContainingClass(File apk, String className, File workDir) throws Exception {
        String dexType = "L" + className.replace('.', '/') + ";";

        try (ZipFile zf = new ZipFile(apk)) {
            Enumeration<? extends ZipEntry> en = zf.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                if (!e.getName().matches("classes(\\d*)\\.dex")) continue;

                File tmp = new File(workDir, e.getName());
                try (InputStream in = zf.getInputStream(e);
                     FileOutputStream out = new FileOutputStream(tmp)) {
                    byte[] buf = new byte[8192]; int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                }

                try {
                    org.jf.dexlib2.dexbacked.DexBackedDexFile dexFile =
                            org.jf.dexlib2.dexbacked.DexBackedDexFile.fromInputStream(
                                    org.jf.dexlib2.Opcodes.getDefault(),
                                    new FileInputStream(tmp));
                    for (org.jf.dexlib2.iface.ClassDef cd : dexFile.getClasses()) {
                        if (cd.getType().equals(dexType)) return tmp;
                    }
                } catch (Throwable ignored) {}
            }
        }
        return null;
    }

    private File injectCallIntoDex(File originalDex, String className,
                                   String smaliCall, File workDir) throws Exception {
        File smaliDir = new File(workDir, "smali_tmp");
        delete(smaliDir);

        org.jf.dexlib2.dexbacked.DexBackedDexFile dexFile =
                org.jf.dexlib2.dexbacked.DexBackedDexFile.fromInputStream(
                        org.jf.dexlib2.Opcodes.getDefault(),
                        new FileInputStream(originalDex));

        org.jf.baksmali.Baksmali.disassembleDexFile(
                dexFile, smaliDir,
                Runtime.getRuntime().availableProcessors(),
                new org.jf.baksmali.BaksmaliOptions());

        String smaliPath = className.replace('.', '/') + ".smali";
        File targetSmali = new File(smaliDir, smaliPath);
        if (!targetSmali.exists()) {
            throw new IllegalStateException("反编译后找不到 smali：" + smaliPath);
        }

        insertInvokeInOnCreate(targetSmali, smaliCall);

        File newDex = new File(workDir, "patched.dex");
        copyFile(originalDex, newDex);
        return newDex;
    }

    private void insertInvokeInOnCreate(File smaliFile, String smaliCall) throws Exception {
        List<String> lines = java.nio.file.Files.readAllLines(smaliFile.toPath());
        List<String> out = new ArrayList<>();
        boolean inOnCreate = false;
        boolean inserted = false;

        for (String line : lines) {
            out.add(line);
            String t = line.trim();

            if (!inOnCreate && t.startsWith(".method")
                    && t.contains("onCreate(Landroid/os/Bundle;)V")) {
                inOnCreate = true;
                continue;
            }
            if (inOnCreate && !inserted && t.startsWith("invoke-super")) {
                out.add("");
                out.add("    " + smaliCall);
                inserted = true;
                inOnCreate = false;
            }
        }

        if (!inserted) throw new IllegalStateException("smali 里没找到 invoke-super，无法插入");
        java.nio.file.Files.write(smaliFile.toPath(), out);
    }

    private int findMaxDexIndex(File apk) throws Exception {
        int max = 0;
        try (ZipFile zf = new ZipFile(apk)) {
            Enumeration<? extends ZipEntry> en = zf.entries();
            while (en.hasMoreElements()) {
                String n = en.nextElement().getName();
                if (n.matches("classes\\d*\\.dex")) {
                    String num = n.replaceAll("\\D", "");
                    int idx = num.isEmpty() ? 1 : Integer.parseInt(num);
                    if (idx > max) max = idx;
                }
            }
        }
        return max;
    }

    private void rebuildApk(File apkIn, File patchedDex, String dexEntryName,
                            File popupDex, String newDexName,
                            File popupAssets, File apkOut) throws Exception {
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(apkIn));
             ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(apkOut))) {

            byte[] buf = new byte[8192];
            ZipEntry entry;
            boolean replaced = false;

            while ((entry = zis.getNextEntry()) != null) {
                if (entry.getName().equals(dexEntryName)) {
                    zos.putNextEntry(new ZipEntry(dexEntryName));
                    try (FileInputStream fis = new FileInputStream(patchedDex)) {
                        int n;
                        while ((n = fis.read(buf)) > 0) zos.write(buf, 0, n);
                    }
                    zos.closeEntry();
                    replaced = true;
                    continue;
                }
                if (entry.getName().equals(newDexName)) continue;

                zos.putNextEntry(new ZipEntry(entry.getName()));
                int n;
                while ((n = zis.read(buf)) > 0) zos.write(buf, 0, n);
                zos.closeEntry();
            }

            if (!replaced) throw new IllegalStateException("APK 里没找到要替换的 dex");

            if (popupDex != null && popupDex.exists()) {
                zos.putNextEntry(new ZipEntry(newDexName));
                try (FileInputStream fis = new FileInputStream(popupDex)) {
                    int n;
                    while ((n = fis.read(buf)) > 0) zos.write(buf, 0, n);
                }
                zos.closeEntry();
            }

            if (popupAssets != null && popupAssets.exists()) {
                appendDirToZip(zos, popupAssets, "assets/");
            }
        }
    }

    private void appendDirToZip(ZipOutputStream zos, File dir, String prefix) throws Exception {
        File[] files = dir.listFiles();
        if (files == null) return;
        byte[] buf = new byte[8192];
        for (File f : files) {
            if (f.isDirectory()) {
                appendDirToZip(zos, f, prefix + f.getName() + "/");
            } else {
                zos.putNextEntry(new ZipEntry(prefix + f.getName()));
                try (FileInputStream fis = new FileInputStream(f)) {
                    int n;
                    while ((n = fis.read(buf)) > 0) zos.write(buf, 0, n);
                }
                zos.closeEntry();
            }
        }
    }

    private String askUserWhichActivity(List<String> activities) {
        final String[] result = {null};
        final CountDownLatch latch = new CountDownLatch(1);

        runOnUiThread(() -> new AlertDialog.Builder(MainActivity.this)
                .setTitle("选择要注入的启动类")
                .setItems(activities.toArray(new String[0]),
                        (d, which) -> {
                            result[0] = activities.get(which);
                            latch.countDown();
                        })
                .setOnCancelListener(d -> latch.countDown())
                .show());

        try {
            latch.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return result[0];
    }

    // =========================================================
    //                          预览页
    // =========================================================
    private void showPreviewPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(colorAttr(com.google.android.material.R.attr.colorSurface));
        scroll.setFillViewport(true);

        LinearLayout root = column();
        scroll.addView(root, lpMatchWrap());
        content.removeAllViews();
        content.addView(scroll, lpMatchMatch());

        LinearLayout header = columnNoPad();
        header.addView(h1("弹窗预览"));
        header.addView(sub("选弹窗包，填入口类与方法，实时预览（含 assets 图片）"));
        root.addView(header);

        MaterialCardView card = mdCardOutlined();
        LinearLayout inner = columnNoPad();
        inner.setPadding(dp(20), dp(16), dp(20), dp(16));
        card.addView(inner);

        TextInputLayout tilClass = new TextInputLayout(this);
        tilClass.setHint("入口类，如 com.aurora.Popup");
        TextInputEditText etClass = new TextInputEditText(this);
        tilClass.addView(etClass);
        inner.addView(tilClass);

        TextInputLayout tilMethod = new TextInputLayout(this);
        tilMethod.setHint("入口方法，如 show");
        TextInputEditText etMethod = new TextInputEditText(this);
        tilMethod.addView(tilMethod == null ? etMethod : etMethod); // 保持结构
        tilMethod.addView(etMethod);
        inner.addView(tilMethod);

        MaterialButton btnZip = mdButtonTonal("选择弹窗包");
        btnZip.setOnClickListener(v -> { pressAnim(v); pickZip(); });
        inner.addView(btnZip);

        MaterialButton btnPreview = mdButtonFilled("预览弹窗");
        LinearLayout.LayoutParams lp = lpMatchWrap();
        lp.topMargin = dp(8);
        inner.addView(btnPreview, lp);

        root.addView(card);

        TextView tvAssets = new TextView(this);
        tvAssets.setTextSize(13);
        tvAssets.setPadding(dp(4), dp(16), dp(4), dp(8));
        tvAssets.setTextColor(colorAttr(com.google.android.material.R.attr.colorOnSurfaceVariant));
        tvAssets.setText("assets 资源预览");
        root.addView(tvAssets);

        LinearLayout assetList = columnNoPad();
        assetList.setPadding(0, 0, 0, dp(16));
        root.addView(assetList);

        // 预览页专属日志
        LogConsole previewLogger = new LogConsole(this);
        LinearLayout.LayoutParams pllp = lpMatchWrap();
        pllp.topMargin = dp(8);
        root.addView(previewLogger.view(), pllp);
        previewLogger.info("等待选择弹窗包…");

        btnPreview.setOnClickListener(v -> {
            pressAnim(v);
            if (zipUri == null) {
                previewLogger.warn("请先选择弹窗包");
                snack("请先选择弹窗包");
                return;
            }
            String cls = etClass.getText() == null ? "" : etClass.getText().toString().trim();
            String mtd = etMethod.getText() == null ? "" : etMethod.getText().toString().trim();
            if (cls.isEmpty() || mtd.isEmpty()) {
                previewLogger.warn("请填写入口类与方法");
                snack("请填写入口类与方法");
                return;
            }
            previewLogger.clear();
            previewLogger.info("开始预览 · " + cls + "#" + mtd);
            doPreview(cls, mtd, assetList, previewLogger);
        });

        animateInStagger(root);
    }

    private void doPreview(String cls, String mtd, LinearLayout assetList, LogConsole log) {
        new Thread(() -> {
            try {
                File dir = new File(getCacheDir(), "popup_preview");
                delete(dir);
                dir.mkdirs();
                unzip(zipUri, dir);
                log.ok("弹窗包解压完成");

                File assetsDir = new File(dir, "assets");
                runOnUiThread(() -> {
                    assetList.removeAllViews();
                    if (assetsDir.exists()) {
                        int before = assetList.getChildCount();
                        renderAssets(assetsDir, assetList);
                        int cnt = assetList.getChildCount() - before;
                        log.info("加载 assets 图片 " + cnt + " 张");
                    } else {
                        log.info("无 assets 目录");
                    }
                });

                File dex = new File(dir, "classes.dex");
                if (!dex.exists()) throw new IllegalStateException("缺少 classes.dex");

                File opt = new File(getCacheDir(), "dex_opt");
                opt.mkdirs();
                DexClassLoader loader = new DexClassLoader(
                        dex.getAbsolutePath(), opt.getAbsolutePath(), null, getClassLoader());
                log.info("DexClassLoader 已创建");

                Class<?> clazz = loader.loadClass(cls);
                log.ok("类加载成功：" + clazz.getName());

                java.lang.reflect.Method m = clazz.getMethod(mtd, Context.class);
                log.info("调用入口：" + mtd + "(Context)");
                m.invoke(null, this);

                runOnUiThread(() -> {
                    log.ok("弹窗已弹出");
                    snack("弹窗已弹出");
                });

            } catch (Exception e) {
                String msg = e.getMessage() == null ? e.toString() : e.getMessage();
                log.error("预览失败：" + msg);
                runOnUiThread(() -> snack("预览失败：" + msg));
            }
        }).start();
    }

    private void renderAssets(File dir, LinearLayout parent) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                renderAssets(f, parent);
            } else if (isImage(f.getName())) {
                try (InputStream in = new FileInputStream(f)) {
                    Bitmap bmp = BitmapFactory.decodeStream(in);
                    if (bmp != null) {
                        ImageView iv = new ImageView(this);
                        iv.setImageBitmap(bmp);
                        iv.setAdjustViewBounds(true);
                        LinearLayout.LayoutParams lp = lpMatchWrap();
                        lp.bottomMargin = dp(8);
                        parent.addView(iv, lp);
                        iv.setAlpha(0f);
                        iv.animate().alpha(1f).setDuration(240).start();
                    }
                } catch (Exception ignored) {}
            }
        }
    }

    private boolean isImage(String name) {
        String n = name.toLowerCase(Locale.ROOT);
        return n.endsWith(".png") || n.endsWith(".jpg") || n.endsWith(".jpeg")
                || n.endsWith(".webp") || n.endsWith(".gif");
    }

    // =========================================================
    //                          注册机页
    // =========================================================
    private void showRegisterPage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(colorAttr(com.google.android.material.R.attr.colorSurface));
        scroll.setFillViewport(true);

        LinearLayout root = column();
        scroll.addView(root, lpMatchWrap());
        content.removeAllViews();
        content.addView(scroll, lpMatchMatch());

        LinearLayout header = columnNoPad();
        header.addView(h1("注册机"));
        header.addView(sub("左滑生成 · 密钥为空则使用默认密钥"));
        root.addView(header);

        MaterialCardView card = mdCardOutlined();
        LinearLayout inner = columnNoPad();
        inner.setPadding(dp(20), dp(16), dp(20), dp(16));
        card.addView(inner);

        TextInputLayout tilSecret = new TextInputLayout(this);
        tilSecret.setHint("自定义密钥（可留空）");
        TextInputEditText etSecret = new TextInputEditText(this);
        etSecret.setText(sp.getString(KEY_SECRET, ""));
        tilSecret.addView(etSecret);
        inner.addView(tilSecret);

        MaterialButton btnGen = mdButtonFilled("生成激活码");
        LinearLayout.LayoutParams glp = lpMatchWrap();
        glp.topMargin = dp(12);
        inner.addView(btnGen, glp);

        TextInputLayout tilCode = new TextInputLayout(this);
        tilCode.setHint("输入激活码校验");
        TextInputEditText etCode = new TextInputEditText(this);
        tilCode.addView(etCode);
        LinearLayout.LayoutParams clp = lpMatchWrap();
        clp.topMargin = dp(12);
        inner.addView(tilCode, clp);

        MaterialButton btnVerify = mdButtonTonal("校验激活码");
        LinearLayout.LayoutParams vlp = lpMatchWrap();
        vlp.topMargin = dp(8);
        inner.addView(btnVerify, vlp);

        root.addView(card);

        TextView tvOut = new TextView(this);
        tvOut.setTextSize(24);
        tvOut.setGravity(Gravity.CENTER);
        tvOut.setPadding(0, dp(28), 0, 0);
        tvOut.setTextColor(colorAttr(com.google.android.material.R.attr.colorPrimary));
        tvOut.setTextIsSelectable(true);
        tvOut.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        root.addView(tvOut);

        LogConsole regLogger = new LogConsole(this);
        LinearLayout.LayoutParams rlp = lpMatchWrap();
        rlp.topMargin = dp(20);
        root.addView(regLogger.view(), rlp);
        regLogger.info("注册机就绪");

        btnGen.setOnClickListener(v -> {
            pressAnim(v);
            String secret = resolveSecret(etSecret);
            sp.edit().putString(KEY_SECRET,
                    etSecret.getText() == null ? "" : etSecret.getText().toString()).apply();
            String code = generateCode(secret);
            tvOut.setTextColor(colorAttr(com.google.android.material.R.attr.colorPrimary));
            tvOut.setText(code);
            tvOut.setAlpha(0f);
            tvOut.setScaleX(0.85f);
            tvOut.animate().alpha(1f).scaleX(1f)
                    .setInterpolator(new OvershootInterpolator(2.2f))
                    .setDuration(320).start();
            regLogger.ok("生成激活码：" + code);
            snack("激活码已生成");
        });

        btnVerify.setOnClickListener(v -> {
            pressAnim(v);
            String secret = resolveSecret(etSecret);
            String input = etCode.getText() == null ? "" : etCode.getText().toString();
            boolean ok = verifyCode(secret, input);
            tvOut.setText(ok ? "✅ 激活成功" : "❌ 激活码无效");
            tvOut.setTextColor(ok ? 0xFF2E7D32 : 0xFFC62828);
            tvOut.setAlpha(0f);
            tvOut.setScaleX(0.9f);
            tvOut.animate().alpha(1f).scaleX(1f)
                    .setInterpolator(new OvershootInterpolator(2f))
                    .setDuration(280).start();
            if (ok) regLogger.ok("校验通过"); else regLogger.error("校验失败");
        });

        GestureDetector gd = new GestureDetector(this,
                new GestureDetector.SimpleOnGestureListener() {
                    @Override
                    public boolean onFling(@Nullable MotionEvent e1, @NonNull MotionEvent e2,
                                           float vx, float vy) {
                        if (e1 != null && e1.getX() - e2.getX() > 120 && Math.abs(vx) > 100) {
                            btnGen.performClick();
                            return true;
                        }
                        return false;
                    }
                });
        root.setOnTouchListener((v, event) -> gd.onTouchEvent(event));

        animateInStagger(root);
    }

    // =========================================================
    //                          公告页
    // =========================================================
    private void showNoticePage() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(colorAttr(com.google.android.material.R.attr.colorSurface));
        scroll.setFillViewport(true);

        LinearLayout root = column();
        scroll.addView(root, lpMatchWrap());
        content.removeAllViews();
        content.addView(scroll, lpMatchMatch());

        LinearLayout header = columnNoPad();
        header.addView(h1("远程公告"));
        header.addView(sub("从服务器拉取最新公告，离线自动回退"));
        root.addView(header);

        MaterialCardView card = mdCardOutlined();
        TextView tvBody = new TextView(this);
        tvBody.setPadding(dp(20), dp(20), dp(20), dp(20));
        tvBody.setTextSize(14);
        tvBody.setLineSpacing(0, 1.35f);
        tvBody.setTextColor(colorAttr(com.google.android.material.R.attr.colorOnSurfaceVariant));
        tvBody.setText("加载中…");
        card.addView(tvBody);
        root.addView(card);

        MaterialButton btn = mdButtonTonal("刷新公告");
        root.addView(btn);

        LogConsole netLogger = new LogConsole(this);
        LinearLayout.LayoutParams nlp = lpMatchWrap();
        nlp.topMargin = dp(16);
        root.addView(netLogger.view(), nlp);

        btn.setOnClickListener(v -> {
            pressAnim(v);
            loadNotice(tvBody, netLogger);
        });

        animateInStagger(root);
        loadNotice(tvBody, netLogger);
    }

    private void loadNotice(TextView tv, LogConsole log) {
        new Thread(() -> {
            log.info("拉取公告：" + NOTICE_URL);
            String text;
            boolean online = true;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(NOTICE_URL).openConnection();
                c.setConnectTimeout(6000);
                c.setReadTimeout(6000);
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(c.getInputStream()))) {
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = r.readLine()) != null) sb.append(line).append('\n');
                    text = sb.toString();
                }
            } catch (Exception e) {
                online = false;
                text = "离线演示公告：\n"
                        + "1. 支持预览 assets 图片。\n"
                        + "2. 弹窗包 = classes.dex + xymods.txt + assets/。\n"
                        + "3. provider authorities 自动替换为宿主包名。";
            }
            final String out = text;
            final boolean ok = online;
            if (ok) log.ok("公告拉取成功"); else log.warn("网络失败，已回退到离线公告");
            runOnUiThread(() -> {
                tv.setText(out);
                tv.setAlpha(0f);
                tv.setTranslationY(dp(10));
                tv.animate().alpha(1f).translationY(0f)
                        .setInterpolator(new DecelerateInterpolator())
                        .setDuration(280).start();
            });
        }).start();
    }

    // =========================================================
    //                          工具方法
    // =========================================================
    private String resolveSecret(EditText et) {
        String s = et.getText() == null ? "" : et.getText().toString().trim();
        return s.isEmpty() ? DEFAULT_SECRET : s;
    }

    private String generateCode(String secret) {
        String ts = minuteStamp(System.currentTimeMillis());
        String h = hmac(secret, ts + "|aurora").substring(0, 16).toUpperCase(Locale.ROOT);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < h.length(); i++) {
            if (i > 0 && i % 4 == 0) sb.append('-');
            sb.append(h.charAt(i));
        }
        return sb.toString();
    }

    private boolean verifyCode(String secret, String input) {
        String clean = input.replace("-", "").trim().toUpperCase(Locale.ROOT);
        if (clean.length() != 16) return false;
        long now = System.currentTimeMillis();
        for (long off = -WINDOW_MS; off <= WINDOW_MS; off += 60_000L) {
            String ts = minuteStamp(now + off);
            String expect = hmac(secret, ts + "|aurora").substring(0, 16)
                    .toUpperCase(Locale.ROOT);
            if (expect.equals(clean)) return true;
        }
        return false;
    }

    private String minuteStamp(long ms) {
        return new SimpleDateFormat("yyyyMMddHHmm", Locale.ROOT).format(new Date(ms));
    }

    private String hmac(String key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] raw = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : raw) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return "0000000000000000";
        }
    }

    private String parseSmaliCall(String config) {
        if (config == null) return null;
        for (String line : config.split("\n")) {
            String t = line.trim();
            if (t.startsWith("invoke-")) return t;
        }
        return null;
    }

    private String shortUri(Uri uri) {
        if (uri == null) return "null";
        String s = uri.getLastPathSegment();
        return s == null ? uri.toString() : s;
    }

    private void unzip(Uri uri, File dir) throws Exception {
        try (ZipInputStream zis = new ZipInputStream(
                getContentResolver().openInputStream(uri))) {
            ZipEntry e; byte[] buf = new byte[8192];
            while ((e = zis.getNextEntry()) != null) {
                File f = new File(dir, e.getName());
                if (e.isDirectory()) { f.mkdirs(); continue; }
                File p = f.getParentFile();
                if (p != null) p.mkdirs();
                try (FileOutputStream os = new FileOutputStream(f)) {
                    int n; while ((n = zis.read(buf)) > 0) os.write(buf, 0, n);
                }
            }
        }
    }

    private String readText(File f) throws Exception {
        try (InputStream in = new FileInputStream(f)) {
            byte[] b = new byte[(int) f.length()];
            int r = in.read(b);
            return new String(b, 0, Math.max(r, 0), StandardCharsets.UTF_8);
        }
    }

    private byte[] readAllBytes(InputStream in) throws Exception {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192]; int n;
        while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
        return bos.toByteArray();
    }

    private void copyFile(File src, File dst) throws Exception {
        try (InputStream in = new FileInputStream(src);
             FileOutputStream out = new FileOutputStream(dst)) {
            byte[] buf = new byte[8192]; int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        }
    }

    private void delete(File f) {
        if (f == null) return;
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) for (File k : kids) delete(k);
        }
        f.delete();
    }

    // =========================================================
    //                     View / Layout 工具
    // =========================================================
    private LinearLayout column() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(20), dp(24), dp(20), dp(24));
        return l;
    }

    private LinearLayout columnNoPad() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    private TextView h1(String t) {
        TextView tv = new TextView(this);
        tv.setText(t);
        tv.setTextSize(26);
        tv.setTypeface(null, Typeface.BOLD);
        tv.setTextColor(colorAttr(com.google.android.material.R.attr.colorOnSurface));
        return tv;
    }

    private TextView sub(String t) {
        TextView tv = new TextView(this);
        tv.setText(t);
        tv.setTextSize(13);
        tv.setLineSpacing(0, 1.3f);
        tv.setTextColor(colorAttr(com.google.android.material.R.attr.colorOnSurfaceVariant));
        tv.setPadding(0, dp(6), 0, dp(20));
        return tv;
    }

    private TextView labelInline(String t) {
        TextView tv = new TextView(this);
        tv.setText(t);
        tv.setTextSize(12);
        tv.setLetterSpacing(0.08f);
        tv.setTypeface(null, Typeface.BOLD);
        tv.setPadding(0, 0, 0, dp(6));
        tv.setTextColor(colorAttr(com.google.android.material.R.attr.colorPrimary));
        return tv;
    }

    /** MD3 Outlined Card */
    private MaterialCardView mdCardOutlined() {
        MaterialCardView c = new MaterialCardView(this);
        c.setRadius(dp(20));
        c.setCardElevation(0f);
        c.setStrokeWidth(dp(1));
        c.setStrokeColor(colorAttr(com.google.android.material.R.attr.colorOutline));
        c.setCardBackgroundColor(colorAttr(com.google.android.material.R.attr.colorSurface));
        LinearLayout.LayoutParams lp = lpMatchWrap();
        lp.bottomMargin = dp(14);
        c.setLayoutParams(lp);
        return c;
    }

    private MaterialButton mdButtonFilled(String text) {
        MaterialButton b = new MaterialButton(this);
        b.setText(text);
        b.setCornerRadius(dp(14));
        b.setLayoutParams(lpMatchWrap());
        return b;
    }

    private MaterialButton mdButtonTonal(String text) {
        MaterialButton b = new MaterialButton(this, null,
                com.google.android.material.R.attr.materialButtonTonalStyle);
        b.setText(text);
        b.setCornerRadius(dp(14));
        b.setLayoutParams(lpMatchWrap());
        return b;
    }

    private int colorAttr(int attr) {
        android.util.TypedValue tv = new android.util.TypedValue();
        getTheme().resolveAttribute(attr, tv, true);
        return tv.data;
    }

    private LinearLayout.LayoutParams lpMatchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private FrameLayout.LayoutParams lpMatchMatch() {
        return new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT);
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void snack(String msg) {
        View v = findViewById(android.R.id.content);
        Snackbar.make(v, msg, Snackbar.LENGTH_SHORT).show();
    }

    // =========================================================
    //                          动效
    // =========================================================
    private void pressAnim(View v) {
        v.animate()
                .scaleX(0.94f).scaleY(0.94f)
                .setDuration(80)
                .setInterpolator(new AccelerateInterpolator())
                .withEndAction(() -> v.animate()
                        .scaleX(1f).scaleY(1f)
                        .setDuration(220)
                        .setInterpolator(new OvershootInterpolator(2.5f))
                        .start())
                .start();
    }

    private void animateIn(View v, long delayMs) {
        v.setAlpha(0f);
        v.setTranslationY(dp(24));
        v.animate()
                .alpha(1f).translationY(0f)
                .setStartDelay(delayMs)
                .setDuration(380)
                .setInterpolator(new DecelerateInterpolator(1.8f))
                .start();
    }

    private void animateInStagger(ViewGroup container) {
        for (int i = 0; i < container.getChildCount(); i++) {
            animateIn(container.getChildAt(i), i * 55L);
        }
    }

    private void animateBottomIcon() {
        View icon = bottomNav.getChildAt(0);
        if (icon != null) {
            icon.setScaleX(0.85f);
            icon.setScaleY(0.85f);
            icon.animate().scaleX(1f).scaleY(1f)
                    .setInterpolator(new OvershootInterpolator(2.2f))
                    .setDuration(260).start();
        }
    }

    private void updateUi(LinearProgressIndicator p, TextView t, int percent, String stage) {
        runOnUiThread(() -> {
            p.setProgressCompat(percent, true);
            t.animate().alpha(0.4f).setDuration(90)
                    .withEndAction(() -> {
                        t.setText(stage + " · " + percent + "%");
                        t.animate().alpha(1f).setDuration(120).start();
                    }).start();
        });
    }

    private void pickApk() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.setType("application/vnd.android.package-archive");
        i.addCategory(Intent.CATEGORY_OPENABLE);
        apkPicker.launch(i);
    }

    private void pickZip() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.setType("*/*");
        i.addCategory(Intent.CATEGORY_OPENABLE);
        zipPicker.launch(i);
    }

    // =========================================================
    //                          LogConsole
    // =========================================================
    /**
     * MD3 风格日志控制台：深色卡片 + 等宽字体 + 分级着色。
     */
    public static class LogConsole {

        public enum Level { INFO, WARN, ERROR, SUCCESS }

        private static class Entry {
            final long time;
            final Level level;
            final String msg;
            Entry(Level l, String m) {
                time = System.currentTimeMillis();
                level = l;
                msg = m;
            }
        }

        private final LinearLayout root;
        private final TextView tvLog;
        private final NestedScrollView scroll;
        private final List<Entry> entries = new ArrayList<>();
        private final Context ctx;

        public LogConsole(Context context) {
            this.ctx = context;

            root = new LinearLayout(context);
            root.setOrientation(LinearLayout.VERTICAL);
            android.graphics.drawable.GradientDrawable bg = new android.graphics.drawable.GradientDrawable();
bg.setColor(0xFF16181B);
bg.setCornerRadius(dp(18));
bg.setStroke(dp(1), 0xFF2B2D30);
root.setBackground(bg);
            root.setPadding(dp(14), dp(12), dp(14), dp(14));

            LinearLayout header = new LinearLayout(context);
            header.setOrientation(LinearLayout.HORIZONTAL);
            header.setGravity(Gravity.CENTER_VERTICAL);

            TextView title = new TextView(context);
            title.setText("● 运行日志");
            title.setTextSize(12);
            title.setLetterSpacing(0.1f);
            title.setTypeface(null, Typeface.BOLD);
            title.setTextColor(0xFFB0BEC5);
            header.addView(title, new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            MaterialButton btnClear = new MaterialButton(context, null,
                    com.google.android.material.R.attr.materialButtonOutlinedStyle);
            btnClear.setText("清空");
            btnClear.setTextSize(10);
            btnClear.setTextColor(0xFFB0BEC5);
            btnClear.setStrokeColor(android.content.res.ColorStateList.valueOf(0xFF3C4043));
            btnClear.setMinHeight(0);
            btnClear.setMinimumHeight(0);
            btnClear.setMinimumWidth(0);
            btnClear.setPadding(dp(14), dp(4), dp(14), dp(4));
            btnClear.setCornerRadius(dp(10));
            btnClear.setOnClickListener(v -> clear());
            header.addView(btnClear);

            root.addView(header);

            View divider = new View(context);
            LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(1));
            dlp.topMargin = dp(8);
            dlp.bottomMargin = dp(8);
            divider.setBackgroundColor(0xFF2B2D30);
            root.addView(divider, dlp);

            scroll = new NestedScrollView(context);
            scroll.setFillViewport(false);
            LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(240));
            root.addView(scroll, slp);

            tvLog = new TextView(context);
            tvLog.setTextSize(11.5f);
            tvLog.setTypeface(Typeface.MONOSPACE);
            tvLog.setTextIsSelectable(true);
            tvLog.setLineSpacing(0, 1.3f);
            tvLog.setTextColor(0xFFE8EAED);
            scroll.addView(tvLog);
        }

        public View view() { return root; }

        public void clear() {
            entries.clear();
            tvLog.setText("");
        }

        public void info(String m)  { add(Level.INFO, m); }
        public void warn(String m)  { add(Level.WARN, m); }
        public void error(String m) { add(Level.ERROR, m); }
        public void ok(String m)    { add(Level.SUCCESS, m); }

        private void add(Level level, String msg) {
            Entry e = new Entry(level, msg);
            entries.add(e);
            postAppend(e);
        }

        private void postAppend(Entry e) {
            runOnUi(() -> {
                String time = new SimpleDateFormat("HH:mm:ss", Locale.ROOT)
                        .format(new Date(e.time));
                String tag = tagOf(e.level);
                String color = colorOf(e.level);

                SpannableStringBuilder sb = new SpannableStringBuilder();

                int s = sb.length();
                sb.append(time).append("  ");
                sb.setSpan(new ForegroundColorSpan(0xFF9AA0A6), s, sb.length(),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

                s = sb.length();
                sb.append(tag).append("  ");
                sb.setSpan(new ForegroundColorSpan(android.graphics.Color.parseColor(color)),
                        s, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                sb.setSpan(new StyleSpan(Typeface.BOLD), s, sb.length(),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

                s = sb.length();
                sb.append(e.msg).append('\n');
                sb.setSpan(new ForegroundColorSpan(0xFFE8EAED), s, sb.length(),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

                tvLog.append(sb);
                scroll.post(() -> scroll.fullScroll(View.FOCUS_DOWN));
            });
        }

        private void runOnUi(Runnable r) {
            if (ctx instanceof Activity) {
                ((Activity) ctx).runOnUiThread(r);
            } else {
                r.run();
            }
        }

        private static String tagOf(Level l) {
            switch (l) {
                case WARN: return "WARN ";
                case ERROR: return "ERROR";
                case SUCCESS: return " OK  ";
                default: return "INFO ";
            }
        }

        private static String colorOf(Level l) {
            switch (l) {
                case WARN: return "#FFB74D";
                case ERROR: return "#EF5350";
                case SUCCESS: return "#66BB6A";
                default: return "#64B5F6";
            }
        }

        private int dp(int v) {
            return (int) (v * ctx.getResources().getDisplayMetrics().density + 0.5f);
        }
    }
}