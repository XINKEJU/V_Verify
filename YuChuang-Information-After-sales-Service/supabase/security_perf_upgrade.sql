-- ============================================================
-- 安全性升级 + 性能优化（2026-07-24）
-- 依赖：pgcrypto（函数位于 extensions 模式），故所有 SECURITY DEFINER
--       函数统一 SET search_path = public, extensions
-- 幂等：可重复执行。
-- ============================================================

-- ── 1. 身份证加密密钥（仅存库内，前端不可见）──────────────
INSERT INTO site_config (key, value)
VALUES ('id_card_key', encode(gen_random_bytes(32), 'hex'))
ON CONFLICT (key) DO NOTHING;

-- ── 2. tickets.id_card 扩为 TEXT 以容纳密文 ───────────────
ALTER TABLE tickets ALTER COLUMN id_card TYPE TEXT;

-- ── 3. 写入时自动加密身份证（SECURITY DEFINER 可读密钥）───
CREATE OR REPLACE FUNCTION trg_encrypt_id_card()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_key text;
BEGIN
  -- 仅当为非空且尚未加密（PGP  armored 以该串开头）时才加密，避免重复加密
  IF NEW.id_card IS NOT NULL
     AND NEW.id_card NOT LIKE '-----BEGIN PGP MESSAGE-----%' THEN
    SELECT value INTO v_key FROM site_config WHERE key = 'id_card_key';
    NEW.id_card := armor(pgp_sym_encrypt(NEW.id_card, v_key));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tickets_encrypt_id_card ON tickets;
CREATE TRIGGER trg_tickets_encrypt_id_card
  BEFORE INSERT OR UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION trg_encrypt_id_card();

-- ── 4. 存量明文重新加密 ───────────────────────────────────
UPDATE tickets
SET id_card = armor(pgp_sym_encrypt(id_card,
                (SELECT value FROM site_config WHERE key = 'id_card_key')))
WHERE id_card IS NOT NULL
  AND id_card NOT LIKE '-----BEGIN PGP MESSAGE-----%';

-- ── 5. get_all_tickets：返回解密后的身份证 + 分页 ─────────
DROP FUNCTION IF EXISTS get_all_tickets(TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION get_all_tickets(
  p_token    TEXT,
  p_phone    TEXT   DEFAULT NULL,
  p_ticket_no TEXT  DEFAULT NULL,
  p_status   TEXT   DEFAULT NULL,
  p_service  TEXT   DEFAULT NULL,
  p_limit    INT    DEFAULT 300,
  p_offset   INT    DEFAULT 0
)
RETURNS TABLE (
  id                UUID,
  ticket_no         VARCHAR(25),
  phone             VARCHAR(11),
  name              VARCHAR(50),
  id_card           TEXT,
  student_no        VARCHAR(20),
  service_type      VARCHAR(30),
  description       TEXT,
  package           VARCHAR(100),
  id_card_front_url TEXT,
  id_card_back_url  TEXT,
  email             VARCHAR(100),
  status            VARCHAR(20),
  assigned_to       VARCHAR(50),
  handled_by        VARCHAR(50),
  result            TEXT,
  created_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_key text;
BEGIN
  PERFORM admin_check(p_token);
  SELECT value INTO v_key FROM site_config WHERE key = 'id_card_key';
  RETURN QUERY
  SELECT
    t.id, t.ticket_no, t.phone, t.name,
    CASE WHEN t.id_card IS NULL THEN NULL
         ELSE pgp_sym_decrypt(dearmor(t.id_card), v_key) END,
    t.student_no, t.service_type, t.description, t.package,
    t.id_card_front_url, t.id_card_back_url, t.email, t.status,
    t.assigned_to, t.handled_by, t.result, t.created_at,
    t.completed_at, t.updated_at
  FROM tickets t
  WHERE (p_phone     IS NULL OR t.phone      = p_phone)
    AND (p_ticket_no IS NULL OR t.ticket_no  = p_ticket_no)
    AND (p_status    IS NULL OR t.status     = p_status)
    AND (p_service   IS NULL OR t.service_type = p_service)
  ORDER BY t.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_all_tickets(TEXT,TEXT,TEXT,TEXT,TEXT,INT,INT) TO anon;

-- ── 6. 登录防爆破 + 过期会话清理 ─────────────────────────
CREATE TABLE IF NOT EXISTS admin_login_guard (
  id          INT PRIMARY KEY DEFAULT 1,
  fails       INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ
);
INSERT INTO admin_login_guard (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
ALTER TABLE admin_login_guard ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION admin_login(p_pass TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  h   text;
  tok text;
  g   admin_login_guard%ROWTYPE;
BEGIN
  -- 清理过期会话（性能 + 卫生）
  DELETE FROM admin_sessions WHERE expires_at < now();

  SELECT * INTO g FROM admin_login_guard WHERE id = 1 FOR UPDATE;
  IF g.locked_until IS NOT NULL AND g.locked_until > now() THEN
    RAISE EXCEPTION 'account_locked';
  END IF;

  SELECT value INTO h FROM site_config WHERE key = 'admin_pass_hash';
  IF h IS NULL OR crypt(p_pass, h) <> h THEN
    UPDATE admin_login_guard
    SET fails = fails + 1,
        locked_until = CASE WHEN fails + 1 >= 5
                           THEN now() + interval '15 minutes'
                           ELSE NULL END
    WHERE id = 1;
    RAISE EXCEPTION 'invalid_credentials';
  END IF;

  UPDATE admin_login_guard SET fails = 0, locked_until = NULL WHERE id = 1;
  tok := encode(gen_random_bytes(24), 'hex');
  INSERT INTO admin_sessions (token, expires_at)
  VALUES (tok, now() + interval '12 hours');
  RETURN tok;
END;
$$;

-- ── 7. admin_update_ticket：校验状态取值 ──────────────────
CREATE OR REPLACE FUNCTION admin_update_ticket(
  p_token      TEXT,
  p_ticket_no  TEXT,
  p_status     TEXT,
  p_note       TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM admin_check(p_token);
  IF p_status IS NULL OR p_status NOT IN
     ('pending','processing','dispatched','completed','closed') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;
  UPDATE tickets SET status = p_status, updated_at = now()
  WHERE ticket_no = p_ticket_no;
  IF p_note IS NOT NULL AND p_note <> '' THEN
    INSERT INTO operation_logs (ticket_id, action, details)
    SELECT id, 'status_change', p_note
    FROM tickets WHERE ticket_no = p_ticket_no;
  END IF;
END;
$$;

-- ── 8. get_my_tickets：手机号格式校验（防越权/脏查）──────
DROP FUNCTION IF EXISTS get_my_tickets(TEXT);
CREATE OR REPLACE FUNCTION get_my_tickets(p_phone TEXT)
RETURNS TABLE (
  ticket_no    TEXT,
  service_type TEXT,
  description  TEXT,
  package      TEXT,
  status       TEXT,
  result       TEXT,
  created_at   TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_phone IS NULL OR p_phone !~ '^[0-9]{11}$' THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT t.ticket_no::text, t.service_type::text, t.description::text, t.package::text,
         t.status::text, t.result::text, t.created_at, t.completed_at
  FROM tickets t
  WHERE t.phone = p_phone
  ORDER BY t.created_at DESC;
END;
$$;

-- ── 9. 性能索引 ───────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tickets_phone_created
  ON tickets(phone, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tickets_service_created
  ON tickets(service_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tickets_status_created
  ON tickets(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_expires
  ON admin_sessions(expires_at);

-- ── 10. 手机号格式约束（现有数据均为 11 位数字，安全）────
ALTER TABLE tickets DROP CONSTRAINT IF EXISTS chk_tickets_phone;
ALTER TABLE tickets
  ADD CONSTRAINT chk_tickets_phone
  CHECK (phone ~ '^[0-9]{11}$');
