package com.xinkeju.vverify;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "VVerify";
    private WebView webView;
    private Button btnExport, btnReset, btnSmartFill;
    private ValueCallback<Uri[]> filePathCallback;
    private final ActivityResultLauncher<Intent> fileChooserLauncher =
            registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), result -> {
                if (filePathCallback == null) return;
                Uri[] results = null;
                if (result.getResultCode() == Activity.RESULT_OK && result.getData() != null) {
                    String dataString = result.getData().getDataString();
                    if (dataString != null) {
                        results = new Uri[]{Uri.parse(dataString)};
                    }
                }
                filePathCallback.onReceiveValue(results);
                filePathCallback = null;
            });

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        // 全屏沉浸式
        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        );

        webView = findViewById(R.id.webview);
        btnExport = findViewById(R.id.btn_export_png);
        btnReset = findViewById(R.id.btn_reset);
        btnSmartFill = findViewById(R.id.btn_smart_fill);

        // JS 接口 - 供网页调用原生下载
        webView.addJavascriptInterface(this, "AndroidNative");

        WebSettings settings = webView.getSettings();

        // 核心 JS 支持
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);

        // viewport 设置：不做自适应，保持 1200px 布局
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);

        // 缓存
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        // 允许文件访问
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);

        // 混合内容（http/https）
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        // WebViewClient
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                injectAndroidAdapter(view);
            }
        });

        // WebChromeClient
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView webView,
                                             ValueCallback<Uri[]> callback,
                                             FileChooserParams fileChooserParams) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;

                Intent intent = fileChooserParams.createIntent();
                try {
                    fileChooserLauncher.launch(intent);
                } catch (ActivityNotFoundException e) {
                    filePathCallback = null;
                    Toast.makeText(MainActivity.this, "无法打开文件选择器", Toast.LENGTH_SHORT).show();
                    return false;
                }
                return true;
            }

            @Override
            public boolean onConsoleMessage(ConsoleMessage consoleMessage) {
                Log.d(TAG, "Console: " + consoleMessage.message() +
                    " (" + consoleMessage.sourceId() + ":" + consoleMessage.lineNumber() + ")");
                return true;
            }
        });

        // DownloadListener
        webView.setDownloadListener((url, userAgent, contentDisposition, mimetype, contentLength) -> {
            handleDownload(url, mimetype);
        });

        // 禁用长按菜单
        webView.setOnLongClickListener(v -> true);
        webView.setHapticFeedbackEnabled(false);

        // 原生按钮事件
        btnSmartFill.setOnClickListener(v -> {
            // 触发智能填写模态弹窗
            webView.evaluateJavascript(
                "if(window.AndroidBridge && AndroidBridge.toggleSmartFill){ AndroidBridge.toggleSmartFill(); }",
                null);
        });

        btnExport.setOnClickListener(v -> {
            // 触发导出 PNG
            webView.evaluateJavascript(
                "if(window.AndroidBridge && AndroidBridge.exportPNG){ AndroidBridge.exportPNG(); } else { document.getElementById('btn-export').click(); }",
                null);
            Toast.makeText(this, "正在导出...", Toast.LENGTH_SHORT).show();
        });

        btnReset.setOnClickListener(v -> {
            new AlertDialog.Builder(this)
                .setTitle("确认")
                .setMessage("确定要重置所有修改吗？")
                .setPositiveButton("确定", (d, w) -> {
                    webView.evaluateJavascript(
                        "if(window.AndroidBridge && AndroidBridge.resetAll){ AndroidBridge.resetAll(); } else { document.getElementById('btn-reset').click(); }",
                        null);
                })
                .setNegativeButton("取消", null)
                .show();
        });

        // 加载本地 HTML
        webView.loadUrl("file:///android_asset/index.html");
    }

    /**
     * 注入安卓端适配脚本：
     * 1. 隐藏 Web 端固定工具栏（原生工具栏替代）
     * 2. 将智能填写表单移动到模态弹窗（保留原始事件绑定）
     * 3. 拦截下载，走原生通道
     * 4. contenteditable 触摸优化
     */
    private void injectAndroidAdapter(WebView view) {
        String js = "(function(){\n" +
            "  if(window.__androidAdapterReady) return;\n" +
            "  window.__androidAdapterReady = true;\n" +
            "\n" +
            "  // === 1. 隐藏 Web 端工具栏 ===\n" +
            "  var wbBar = document.getElementById('wb-bar');\n" +
            "  if(wbBar) wbBar.style.display = 'none';\n" +
            "  // 移除工具栏占位 spacer div\n" +
            "  var spacers = document.querySelectorAll('div[style*=\"height:84px\"]');\n" +
            "  spacers.forEach(function(s){ s.style.height = '0px'; });\n" +
            "\n" +
            "  // === 2. 创建智能填写模态弹窗 ===\n" +
            "  var modal = document.createElement('div');\n" +
            "  modal.id = 'android-smart-modal';\n" +
            "  modal.style.cssText = 'display:none;position:fixed;top:0;left:0;right:0;bottom:0;z-index:999999;background:rgba(0,0,0,0.7);overflow:auto;';\n" +
            "\n" +
            "  var panel = document.createElement('div');\n" +
            "  panel.style.cssText = 'position:relative;top:20px;margin:0 auto;width:1100px;max-width:95%;background:#fff;border-radius:12px;padding:24px 28px;box-shadow:0 8px 32px rgba(0,0,0,0.3);';\n" +
            "\n" +
            "  // 标题栏\n" +
            "  var header = document.createElement('div');\n" +
            "  header.style.cssText = 'display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;padding-bottom:14px;border-bottom:2px solid #1a56db;';\n" +
            "  var title = document.createElement('span');\n" +
            "  title.style.cssText = 'font-size:20px;font-weight:700;color:#1a56db;';\n" +
            "  title.textContent = '智能填写';\n" +
            "  var closeBtn = document.createElement('button');\n" +
            "  closeBtn.textContent = '\\u2715 关闭';\n" +
            "  closeBtn.style.cssText = 'padding:8px 18px;border:none;border-radius:6px;background:#e74c3c;color:#fff;font-size:15px;cursor:pointer;touch-action:manipulation;';\n" +
            "  closeBtn.onclick = function(){ modal.style.display = 'none'; };\n" +
            "  header.appendChild(title);\n" +
            "  header.appendChild(closeBtn);\n" +
            "  panel.appendChild(header);\n" +
            "\n" +
            "  // 将原始 wb-smart 表单移动到弹窗中（保留所有事件绑定）\n" +
            "  var origSmart = document.getElementById('wb-smart');\n" +
            "  if(origSmart){\n" +
            "    origSmart.style.cssText = 'display:flex;flex-direction:column;gap:18px;padding:8px 0;';\n" +
            "    // 调整 label 样式使其在弹窗中更易操作\n" +
            "    origSmart.querySelectorAll('label').forEach(function(lb){\n" +
            "      lb.style.cssText = 'display:flex;align-items:center;gap:10px;font-size:16px;color:#333;white-space:nowrap;';\n" +
            "    });\n" +
            "    // 调整 input/select 样式\n" +
            "    origSmart.querySelectorAll('input, select').forEach(function(inp){\n" +
            "      inp.style.cssText = 'padding:10px 14px;border:1px solid #ccc;border-radius:6px;font-size:16px;background:#fff;color:#333;';\n" +
            "      if(inp.tagName === 'INPUT') inp.style.minWidth = '140px';\n" +
            "      if(inp.tagName === 'SELECT') inp.style.minWidth = '100px';\n" +
            "    });\n" +
            "    // 调整按钮样式\n" +
            "    origSmart.querySelectorAll('button').forEach(function(btn){\n" +
            "      btn.style.cssText = 'padding:12px 28px;border:none;border-radius:6px;background:#ffd700;color:#1a56db;font-weight:700;font-size:17px;cursor:pointer;touch-action:manipulation;margin-top:8px;align-self:flex-start;';\n" +
            "    });\n" +
            "    panel.appendChild(origSmart);\n" +
            "  }\n" +
            "\n" +
            "  modal.appendChild(panel);\n" +
            "  // 点击遮罩关闭\n" +
            "  modal.addEventListener('click', function(e){\n" +
            "    if(e.target === modal) modal.style.display = 'none';\n" +
            "  });\n" +
            "  document.body.appendChild(modal);\n" +
            "\n" +
            "  // === 3. AndroidBridge 接口 ===\n" +
            "  window.AndroidBridge = {\n" +
            "    toggleSmartFill: function(){\n" +
            "      var m = document.getElementById('android-smart-modal');\n" +
            "      if(m){\n" +
            "        m.style.display = (m.style.display === 'none' || !m.style.display) ? 'block' : 'none';\n" +
            "      }\n" +
            "    },\n" +
            "    exportPNG: function(){\n" +
            "      var btn = document.getElementById('btn-export');\n" +
            "      if(btn) btn.click();\n" +
            "    },\n" +
            "    resetAll: function(){\n" +
            "      var btn = document.getElementById('btn-reset');\n" +
            "      if(btn) btn.click();\n" +
            "    }\n" +
            "  };\n" +
            "\n" +
            "  // === 4. 拦截下载，走原生通道 ===\n" +
            "  document.addEventListener('click', function(e){\n" +
            "    var a = e.target.closest('a');\n" +
            "    if(a && a.download && a.href){\n" +
            "      e.preventDefault();\n" +
            "      e.stopPropagation();\n" +
            "      if(window.AndroidNative){\n" +
            "        window.AndroidNative.downloadFile(a.href, a.download);\n" +
            "      }\n" +
            "      return false;\n" +
            "    }\n" +
            "  }, true);\n" +
            "\n" +
            "  // === 5. contenteditable 触摸优化 ===\n" +
            "  document.querySelectorAll('[contenteditable]').forEach(function(el){\n" +
            "    el.addEventListener('touchstart', function(){\n" +
            "      this.focus();\n" +
            "    }, {passive: true});\n" +
            "  });\n" +
            "\n" +
            "  console.log('[AndroidAdapter] Injected successfully');\n" +
            "})();\n";
        view.evaluateJavascript(js, null);
    }

    /**
     * 处理下载（PNG 导出）
     */
    private void handleDownload(String url, String mimetype) {
        try {
            if (url.startsWith("data:")) {
                saveDataUrlToFile(url, mimetype);
            } else {
                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                startActivity(intent);
            }
        } catch (Exception e) {
            Log.e(TAG, "Download error", e);
            Toast.makeText(this, "下载失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    /**
     * 将 data:image/png;base64,... 保存到下载目录
     */
    private void saveDataUrlToFile(String dataUrl, String mimetype) {
        try {
            String[] parts = dataUrl.split(",");
            String header = parts[0];
            String base64Data = parts.length > 1 ? parts[1] : "";

            String ext = "png";
            if (header.contains("jpeg") || header.contains("jpg")) ext = "jpg";
            else if (header.contains("webp")) ext = "webp";

            String timestamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.CHINA).format(new Date());
            String filename = "学信档案_" + timestamp + "." + ext;

            byte[] bytes = android.util.Base64.decode(base64Data, android.util.Base64.DEFAULT);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                android.content.ContentResolver resolver = getContentResolver();
                android.content.ContentValues values = new android.content.ContentValues();
                values.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, filename);
                values.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "image/" + ext);
                values.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);

                Uri uri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (uri != null) {
                    java.io.OutputStream os = resolver.openOutputStream(uri);
                    if (os != null) {
                        os.write(bytes);
                        os.close();
                    }
                }
                Toast.makeText(this, "已保存到 Download/" + filename, Toast.LENGTH_LONG).show();
            } else {
                File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                if (dir != null && !dir.exists()) dir.mkdirs();
                File file = new File(dir, filename);
                FileOutputStream fos = new FileOutputStream(file);
                fos.write(bytes);
                fos.close();

                Intent scanIntent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
                scanIntent.setData(Uri.fromFile(file));
                sendBroadcast(scanIntent);

                Toast.makeText(this, "已保存: " + file.getAbsolutePath(), Toast.LENGTH_LONG).show();
            }
        } catch (Exception e) {
            Log.e(TAG, "saveDataUrlToFile error", e);
            Toast.makeText(this, "保存失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    /**
     * JS 接口 - 供网页调用原生下载
     */
    @android.webkit.JavascriptInterface
    public void downloadFile(String dataUrl, String filename) {
        runOnUiThread(() -> saveDataUrlToFile(dataUrl, "image/png"));
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            // 先检查智能填写弹窗是否打开
            webView.evaluateJavascript(
                "(function(){ var m=document.getElementById('android-smart-modal'); if(m && m.style.display==='block'){ m.style.display='none'; return 'close'; } return 'goback'; })()",
                value -> {
                    if ("goback".equals(value) && webView.canGoBack()) {
                        webView.goBack();
                    }
                });
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
