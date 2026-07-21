/**
 * 学信档案截图工具 — Puppeteer (Chromium) 所见即所得高清截图
 * 
 * 用法: node 学信档案截图工具.js
 * 输出: 截图输出.png (3x Retina 超高清)
 * 
 * 依赖: 需要安装 puppeteer (npm install puppeteer)
 * 优先在以下位置查找 puppeteer:
 *   1. 当前目录的 node_modules
 *   2. ~/node_modules
 *   3. NODE_PATH 环境变量指定的目录
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const Module = require('module');

const HTML_PATH = path.join(__dirname, '学信档案编辑器.html');
const OUTPUT_PATH = path.join(__dirname, '截图输出.png');
const PORT = 19876;
const VIEWPORT_W = 1280;
const SCALE = 3; // 3x Retina 超高清

// 自动定位 puppeteer 路径
function resolvePuppeteer() {
  // 1. 当前目录
  try { return require(path.join(__dirname, 'node_modules', 'puppeteer')); } catch (e) {}
  // 2. ~/node_modules
  const home = process.env.HOME || process.env.USERPROFILE;
  if (home) {
    try { return require(path.join(home, 'node_modules', 'puppeteer')); } catch (e) {}
    try { return require(path.join(home, '.workbuddy', 'binaries', 'node', 'workspace', 'node_modules', 'puppeteer')); } catch (e) {}
  }
  // 3. NODE_PATH
  return require('puppeteer');
}

function startServer(htmlPath, port) {
  return new Promise((resolve) => {
    const html = fs.readFileSync(htmlPath, 'utf-8');
    const server = http.createServer((req, res) => {
      if (req.url === '/' || req.url === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Access-Control-Allow-Origin': '*' });
        res.end(html);
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });
    server.listen(port, () => { console.log(`[服务器] http://localhost:${port}`); resolve(server); });
  });
}

async function takeScreenshot() {
  let puppeteer;
  try {
    puppeteer = resolvePuppeteer();
  } catch (e) {
    console.error('❌ 找不到 puppeteer，请先安装:');
    console.error('   npm install puppeteer');
    process.exit(1);
  }
  
  console.log('[Puppeteer] 启动 Chromium...');
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  try {
    const page = await browser.newPage();

    // 第一步：用超高的视口加载，让完整页面布局（包括 sticky footer）
    await page.setViewport({ width: VIEWPORT_W, height: 3000, deviceScaleFactor: SCALE });

    console.log(`[Puppeteer] 加载页面 http://localhost:${PORT}`);
    await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle0', timeout: 30000 });

    // 等待字体
    console.log('[Puppeteer] 等待字体加载...');
    await page.evaluate(() => document.fonts.ready);
    await new Promise(r => setTimeout(r, 1500));

    // 第二步：在正确布局后，测量真实内容高度
    const pageMetrics = await page.evaluate(() => {
      const body = document.body;
      const html = document.documentElement;

      // 找到最后一个可见元素的底部
      const allElements = body.querySelectorAll('*');
      let maxBottom = 0;
      allElements.forEach(el => {
        const rect = el.getBoundingClientRect();
        if (rect.bottom > maxBottom && rect.width > 0 && rect.height > 0) {
          maxBottom = rect.bottom;
        }
      });

      return {
        bodyScroll: body.scrollHeight,
        docScroll: html.scrollHeight,
        lastElementBottom: maxBottom,
      };
    });

    const totalHeight = Math.ceil(Math.max(
      pageMetrics.bodyScroll,
      pageMetrics.docScroll,
      pageMetrics.lastElementBottom
    ));
    console.log(`[Puppeteer] 页面总高度: ${totalHeight}px`);

    // 第三步：把视口调成正好容纳全部内容
    await page.setViewport({ width: VIEWPORT_W, height: totalHeight + 20, deviceScaleFactor: SCALE });
    await new Promise(r => setTimeout(r, 500));

    // 第四步：用 clip 精确截取
    await page.screenshot({
      path: OUTPUT_PATH,
      type: 'png',
      clip: { x: 0, y: 0, width: VIEWPORT_W, height: totalHeight }
    });

    const stats = fs.statSync(OUTPUT_PATH);
    const imgWidth = VIEWPORT_W * SCALE;
    const imgHeight = Math.round(totalHeight * SCALE);
    console.log(`\n✅ 截图完成: ${OUTPUT_PATH}`);
    console.log(`   文件大小: ${(stats.size / 1024).toFixed(0)} KB`);
    console.log(`   图片尺寸: ${imgWidth} × ${imgHeight}px`);
    console.log(`   分辨率: ${SCALE}x Retina`);
    console.log(`   渲染引擎: Chromium (与浏览器完全一致)`);

  } finally {
    await browser.close();
  }
}

async function main() {
  console.log('═══ 学信档案截图工具 (Puppeteer Chromium) ═══\n');

  if (!fs.existsSync(HTML_PATH)) {
    console.error(`❌ 找不到 ${HTML_PATH}`);
    process.exit(1);
  }

  const server = await startServer(HTML_PATH, PORT);
  try { await takeScreenshot(); }
  catch (e) { console.error('截图失败:', e.message); }
  finally { server.close(); }

  if (process.platform === 'darwin') {
    exec(`open "${OUTPUT_PATH}"`);
  }
}

main();
