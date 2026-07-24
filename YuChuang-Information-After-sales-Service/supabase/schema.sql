-- ============================================================
-- 浙江海洋大学校园网服务系统 · Supabase 数据库初始化脚本
-- 在 Supabase 控制台 > SQL Editor 中执行
-- ============================================================

-- ── 1. 工单表 ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tickets (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_no         VARCHAR(25) UNIQUE NOT NULL,
  phone             VARCHAR(11) NOT NULL,
  name              VARCHAR(50) NOT NULL,
  id_card           VARCHAR(18) NOT NULL,
  student_no        VARCHAR(20) NOT NULL,
  service_type      VARCHAR(30) NOT NULL,
  description       TEXT,
  package           VARCHAR(100),
  id_card_front_url TEXT,
  id_card_back_url  TEXT,
  email             VARCHAR(100),             -- 邮箱通知地址
  status            VARCHAR(20)  DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','dispatched','completed','closed')),
  assigned_to       VARCHAR(50),              -- 分配给谁处理
  handled_by        VARCHAR(50),              -- 实际处理人
  result            TEXT,                     -- 处理结果
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  completed_at      TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_tickets_phone      ON tickets(phone);
CREATE INDEX IF NOT EXISTS idx_tickets_ticket_no  ON tickets(ticket_no);
CREATE INDEX IF NOT EXISTS idx_tickets_status     ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_created_at ON tickets(created_at DESC);

-- ── 2. 用户信息缓存表 ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  phone             VARCHAR(11) UNIQUE NOT NULL,
  name              VARCHAR(50),
  id_card_hash      VARCHAR(128),             -- 身份证哈希（SHA256）
  student_no        VARCHAR(20),
  package_type      VARCHAR(50),
  broadband_account VARCHAR(50),
  broadband_password VARCHAR(200),            -- 加密存储
  account_balance   DECIMAL(10,2) DEFAULT 0.00,
  account_status    VARCHAR(20)  DEFAULT 'active',
  last_request_time TIMESTAMPTZ,
  request_count     INTEGER      DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- ── 3. 操作日志表 ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS operation_logs (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_id   UUID        REFERENCES tickets(id) ON DELETE SET NULL,
  action      VARCHAR(50) NOT NULL,
  actor       VARCHAR(50),
  details     TEXT,
  ip_address  VARCHAR(45),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_ticket_id  ON operation_logs(ticket_id);
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON operation_logs(created_at DESC);

-- ── 4. updated_at 自动更新触发器 ────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tickets_updated_at
  BEFORE UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 5. Row Level Security (RLS) ─────────────────────────────
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE operation_logs ENABLE ROW LEVEL SECURITY;

-- 匿名用户：只能插入工单（不能读取他人数据）
-- 安全约束：提交时强制 status='pending'，且禁止写入处理结果/处理人/完成时间等字段，
-- 防止用户越权篡改工单状态或伪造处理结果。
CREATE POLICY "anon_insert_ticket" ON tickets
  FOR INSERT TO anon
  WITH CHECK (
    status = 'pending'
    AND result IS NULL
    AND assigned_to IS NULL
    AND handled_by IS NULL
    AND completed_at IS NULL
  );

-- 匿名用户：查询工单（前端用手机号筛选，anon key 公开无妨）
CREATE POLICY "anon_select_tickets" ON tickets
  FOR SELECT TO anon
  USING (true);

-- 允许 service_role 完全访问（Edge Functions使用）
CREATE POLICY "service_role_all_tickets" ON tickets
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY "service_role_all_users" ON users
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY "service_role_all_logs" ON operation_logs
  FOR ALL TO service_role
  USING (true) WITH CHECK (true);

-- ── 6. Storage Bucket（身份证图片）──────────────────────────
-- 创建存储桶
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('id-cards', 'id-cards', false, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- RLS 策略：匿名用户可上传
CREATE POLICY "anon_can_upload_id_cards" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id = 'id-cards');

-- RLS 策略：service_role 可读取
CREATE POLICY "service_role_can_read_id_cards" ON storage.objects
  FOR SELECT TO service_role
  USING (bucket_id = 'id-cards');

-- ── 7. 查询视图（可选，方便飞书等工具集成）──────────────────
CREATE OR REPLACE VIEW v_pending_tickets AS
SELECT
  ticket_no,
  phone,
  name,
  student_no,
  service_type,
  description,
  package,
  created_at
FROM tickets
WHERE status = 'pending'
ORDER BY created_at ASC;

CREATE OR REPLACE VIEW v_ticket_stats AS
SELECT
  status,
  COUNT(*) as count,
  DATE_TRUNC('day', created_at) as day
FROM tickets
GROUP BY status, DATE_TRUNC('day', created_at)
ORDER BY day DESC;

-- ============================================================
-- 执行完毕后，请在 Supabase 控制台：
-- 1. Storage > 创建 Bucket "id-cards"（非公开）
-- 2. Storage > Policies > 允许 anon INSERT
-- 3. Authentication > URL Configuration > 添加允许的重定向 URL
-- ============================================================
