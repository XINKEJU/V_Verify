/**
 * 全局配置文件
 * 部署前请替换以下配置项
 */
const APP_CONFIG = {
  // ===== Supabase 配置 =====
  // 在 https://app.supabase.com 项目 Settings > API 中获取
  SUPABASE_URL: 'https://cmylagvqmqxledemfdyn.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNteWxhZ3ZxbXF4bGVkZW1mZHluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0Njk4NzgsImV4cCI6MjA5NjA0NTg3OH0.oHTj0PhqejLM3-Ur0gxVyDq1UrQK4d4G_MRpMAx2edo',

  // ===== 应用基础路径 =====
  // 部署后的域名（CloudStudio 分享链接），例如 https://xxxxxx.app.codebuddy.work
  APP_BASE_URL: 'https://b7fe3301680f4b0db0136418e27a59ea.app.codebuddy.work',

  // ===== Edge Function URL =====
  SUBMIT_API: 'https://cmylagvqmqxledemfdyn.supabase.co/functions/v1/process-ticket',
  QUERY_API:  'https://cmylagvqmqxledemfdyn.supabase.co/functions/v1/query-ticket',

  // ===== 邮件通知（可选，使用Supabase内置SMTP或第三方如Resend）=====
  // 留空则禁用邮件通知功能
  EMAIL_NOTIFY_ENABLED: true,

  // ===== 业务配置 =====
  // 用户端可选服务（不含账号密码查询、不含费用余额）
  USER_SERVICE_TYPES: [
    { value: 'package_change',  label: '套餐变更/叠加减免' },
    { value: 'broadband_open',  label: '开通校园宽带' },
    { value: 'broadband_close', label: '关闭校园宽带' },
    { value: 'trouble_report',  label: '宽带故障报修' },
    { value: 'cancel_account',  label: '账户销户申请' },
  ],
  // 管理员端服务（含账号密码查询，无费用余额）
  ADMIN_SERVICE_TYPES: [
    { value: 'package_change',  label: '套餐变更/叠加减免' },
    { value: 'broadband_open',  label: '开通校园宽带' },
    { value: 'broadband_close', label: '关闭校园宽带' },
    { value: 'query_account',   label: '账号密码查询' },
    { value: 'trouble_report',  label: '宽带故障报修' },
    { value: 'cancel_account',  label: '账户销户申请' },
  ],

  PACKAGES: [
    { value: 'basic',    label: '基础套餐 20元/月' },
    { value: 'standard', label: '标准套餐 40元/月' },
    { value: 'premium',  label: '高级套餐 60元/月' },
    { value: 'addon',    label: '叠加流量包 10元/10GB' },
  ],

  STATUS_MAP: {
    pending:    { label: '待处理', color: '#FF9500' },
    processing: { label: '处理中', color: '#E60012' },
    dispatched: { label: '已派发联通', color: '#5856D6' },
    completed:  { label: '已完成', color: '#34C759' },
    closed:     { label: '已关闭', color: '#8E8E93' },
  },

  SERVICE_TYPE_MAP: {
    package_change:  '套餐变更',
    broadband_open:  '开通宽带',
    broadband_close: '关闭宽带',
    query_account:   '账号密码查询',
    trouble_report:  '故障报修',
    cancel_account:  '账户销户',
  },

  // ===== 需要上传身份证的服务类型 =====
  // 故障报修通常仅为网络问题，无需身份核验，故默认排除，减少用户不必要摩擦。
  // 如需调整，修改此数组即可（与前端逻辑解耦）。
  ID_REQUIRED_TYPES: [
    'package_change',
    'broadband_open',
    'broadband_close',
    'cancel_account',
  ],
};
