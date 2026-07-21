#!/usr/bin/env python3
"""将 html2canvas.min.js 内嵌到学信档案编辑器.html 中"""
import sys

HTML_PATH = "/Users/xinkeju/Desktop/联通/学信档案编辑器.html"
H2C_PATH = "/Users/xinkeju/.workbuddy/binaries/node/workspace/node_modules/html2canvas/dist/html2canvas.min.js"

with open(HTML_PATH, 'r', encoding='utf-8') as f:
    html = f.read()

with open(H2C_PATH, 'r', encoding='utf-8') as f:
    h2c = f.read()

# 检查是否已内嵌
if 'html2canvas 1.4.1' in html and '__html2canvasEmbedded__' in html:
    print("已内嵌，无需重复处理")
    sys.exit(0)

# 在 dom-to-image-more 之前插入 html2canvas
# 找到 <script>/*! dom-to-image-more ...</script> 的位置
MARKER = '<script>/*! dom-to-image-more'
idx = html.find(MARKER)
if idx < 0:
    print("❌ 找不到 dom-to-image-more 标记")
    sys.exit(1)

# 插入 html2canvas
# 用 IIFE 包裹防止污染全局，但暴露 html2canvas 函数
insertion = f'''<script>
/*! html2canvas 1.4.1 - inlined for offline PUA font rendering */
window.__html2canvasEmbedded__ = true;
{h2c}
</script>
'''
new_html = html[:idx] + insertion + html[idx:]

with open(HTML_PATH, 'w', encoding='utf-8') as f:
    f.write(new_html)

print(f"✅ 已内嵌 html2canvas")
print(f"   源 HTML: {len(html):,} bytes")
print(f"   新 HTML: {len(new_html):,} bytes")
print(f"   增加:    {len(new_html) - len(html):,} bytes")
