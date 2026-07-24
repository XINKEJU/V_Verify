# 浙江海洋大学校园网服务系统

> 零下载、表单化校园网售后服务平台  
> 学生扫码 → 填写H5表单 → 飞书工作流 → 微信/邮件通知

---

## 项目结构

```
├── index.html                          # 学生端：服务申请表单
├── query.html                          # 学生端：工单进度查询
├── src/
│   └── config.js                       # 全局配置（需填写你的密钥）
├── supabase/
│   ├── schema.sql                      # 数据库初始化脚本
│   └── functions/
│       ├── process-ticket/index.js     # Edge Function：处理新工单
│       └── query-ticket/index.js       # Edge Function：查询工单
└── README.md
```

---

## 一、注册并配置 Supabase（免费）

### 1.1 注册账号
前往 [https://app.supabase.com](https://app.supabase.com) 注册并创建项目。

### 1.2 初始化数据库
1. 进入项目 → **SQL Editor**
2. 粘贴 `supabase/schema.sql` 全部内容并执行

### 1.3 创建 Storage Bucket
1. 进入项目 → **Storage** → 点击 "New bucket"
2. Bucket 名称填 `id-cards`，**不勾选** "Public bucket"（私有存储）
3. 进入 `id-cards` bucket → **Policies** → 添加策略：
   - INSERT：允许 `anon`（匿名用户可上传）
   - SELECT：仅允许 `service_role`（保护隐私）

### 1.4 获取配置信息
进入项目 → **Settings** → **API**，记录：
- `Project URL`（即 `SUPABASE_URL`）
- `anon public` key（即 `SUPABASE_ANON_KEY`）

---

## 二、配置前端

打开 `src/config.js`，填写：

```javascript
SUPABASE_URL:      'https://xxxxxxxxxx.supabase.co',  // 你的项目 URL
SUPABASE_ANON_KEY: 'eyJhbGciOiJ...',                  // anon key
APP_BASE_URL:      'https://YOUR_DOMAIN.app.codebuddy.work', // 部署后的域名（CloudStudio 分享链接，选填）
```

---

## 三、部署 Edge Functions（可选，用于飞书同步和邮件通知）

### 3.1 安装 Supabase CLI
```bash
npm install -g supabase
supabase login
```

### 3.2 设置 Secrets（环境变量）
```bash
# 必填
supabase secrets set FEISHU_APP_ID=xxx
supabase secrets set FEISHU_APP_SECRET=xxx
supabase secrets set FEISHU_APP_TOKEN=xxx   # 多维表格 app_token
supabase secrets set FEISHU_TABLE_ID=xxx    # 多维表格 table_id

# 可选（邮件通知，使用 Resend 免费服务）
supabase secrets set RESEND_API_KEY=re_xxx
supabase secrets set FROM_EMAIL=noreply@yourdomain.com
```

### 3.3 部署函数
```bash
supabase functions deploy process-ticket
supabase functions deploy query-ticket
```

> **如果不使用飞书/邮件通知**，可以跳过 Edge Functions 部署。  
> 工单数据会直接写入 Supabase 数据库，在控制台的 Table Editor 中即可查看。

---

## 四、部署前端到 CloudStudio（国内可访问，免费）

本项目已将全部前端依赖（Vue 3、Vant 4、Supabase JS）本地化到 `vendor/` 目录，
页面运行时不再请求任何海外 CDN，可在国内网络环境直接访问。

部署步骤：
1. 将 `index.html`、`query.html`、`src/`、`vendor/` 作为静态站点上传到 CloudStudio 静态托管；
2. 以根目录的 `index.html` 作为站点入口；
3. 部署完成后，将分享链接填入 `src/config.js` 的 `APP_BASE_URL`（选填，页面跳转使用相对路径，可不填）。

> 说明：原文档中的 Vercel 部署方式因海外节点在国内访问不稳定，已改为 CloudStudio 静态托管。
> 若仍需使用 Vercel，请注意其域名在国内可能被限制。

---

## 五、配置飞书多维表格

### 5.1 创建多维表格
参考开发文档第4节，在飞书中创建含以下字段的表格：

| 字段 | 类型 |
|------|------|
| 工单号 | 文本 |
| 手机号 | 文本 |
| 姓名 | 文本 |
| 身份证号 | 文本（脱敏） |
| 学号 | 文本 |
| 需求类型 | 单选 |
| 需求描述 | 多行文本 |
| 套餐 | 单选 |
| 状态 | 单选：待处理/处理中/已派发联通/已完成/已关闭 |
| 提交时间 | 日期时间 |
| 处理人 | 人员 |
| 处理结果 | 多行文本 |
| 完成时间 | 日期时间 |
| 身份证正面链接 | 文本 |
| 身份证反面链接 | 文本 |

### 5.2 获取 app_token 和 table_id
- 打开多维表格，URL 中 `/base/` 后面的字符串即 `app_token`
- 进入飞书开放平台 → 创建应用 → 获取 `App ID` 和 `App Secret`
- 给应用授权多维表格的读写权限

---

## 六、生成推广二维码

将以下 URL 生成二维码，打印成海报张贴在宿舍楼道、食堂、教学楼：

```
https://你的部署域名/index.html
```

推荐使用草料二维码（cli.im）生成美观的二维码海报。

---

## 七、工作流程

```
学生扫码 → 填写4步表单 → 提交
     ↓
Supabase 数据库存储 + 图片存储
     ↓
Edge Function 同步到飞书多维表格
     ↓
客服在飞书中查看待处理工单
     ↓
处理完成 → 更新状态
     ↓
（如开启邮件通知）→ 邮件通知学生
```

---

## 八、成本明细

| 服务 | 用途 | 费用 |
|------|------|------|
| Supabase 免费层 | 数据库 500MB + 存储 1GB | 免费 |
| CloudStudio 静态托管 | H5 页面托管（国内可访问） | 免费 |
| 飞书多维表格 | 工单协同管理 | 免费 |
| Resend 免费层 | 邮件通知 100封/天 | 免费 |
| **合计** | | **¥0/月** |

---

## 常见问题

**Q：图片上传失败？**  
A：检查 Supabase Storage 中 `id-cards` bucket 是否创建，以及 INSERT Policy 是否允许 `anon`。

**Q：提交成功但飞书没有数据？**  
A：飞书配置是可选的，主数据在 Supabase 数据库。在 Supabase → Table Editor → tickets 表中可以查看所有工单。

**Q：工单查询返回空？**  
A：查询走 `get_my_tickets` 安全 RPC，仅返回「该手机号自己的工单」，且匿名角色已无法直接 `SELECT` 全表（安全加固）。若返回空，请确认输入的手机号与提交时一致；管理端查看全部工单请用 Supabase Studio 或部署后的 `query-ticket` Edge Function。
