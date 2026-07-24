-- ============================================================
-- 管理员端：认证与会话、全量查询、改单
-- 设计要点：
--   1. 管理员口令以 bcrypt 哈希存于 site_config，前端从不接触明文口令。
--   2. 登录成功后返回随机会话 token（存 sessionStorage），后续 RPC 必须携带。
--   3. 所有管理员 RPC 均为 SECURITY DEFINER，先校验 token 再绕过 RLS 操作。
--   4. 用户端数据隔离不受影响：anon 仍无法 SELECT tickets，只能走 get_my_tickets。
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 站点配置（口令哈希等）
CREATE TABLE IF NOT EXISTS site_config (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- 默认管理员口令：admin123  —— 请务必在 Supabase Studio 中修改 value
INSERT INTO site_config (key, value)
VALUES ('admin_pass_hash', crypt('admin123', gen_salt('bf')))
ON CONFLICT (key) DO NOTHING;

-- 管理员会话表
CREATE TABLE IF NOT EXISTS admin_sessions (
  token       TEXT PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL
);

-- 登录：校验口令，成功写入会话并返回 token
CREATE OR REPLACE FUNCTION admin_login(p_pass TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  h   TEXT;
  tok TEXT;
BEGIN
  SELECT value INTO h FROM site_config WHERE key = 'admin_pass_hash';
  IF h IS NULL OR crypt(p_pass, h) <> h THEN
    RAISE EXCEPTION 'invalid_credentials';
  END IF;
  tok := encode(gen_random_bytes(24), 'hex');
  INSERT INTO admin_sessions (token, expires_at)
  VALUES (tok, now() + interval '12 hours');
  RETURN tok;
END;
$$;

-- 登出：销毁会话
CREATE OR REPLACE FUNCTION admin_logout(p_token TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  DELETE FROM admin_sessions WHERE token = p_token;
END;
$$;

-- 会话校验：无效或过期则抛错
CREATE OR REPLACE FUNCTION admin_check(p_token TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_sessions
    WHERE token = p_token AND expires_at > now()
  ) THEN
    RAISE EXCEPTION 'session_invalid';
  END IF;
END;
$$;

-- 全量查询工单（管理员）
CREATE OR REPLACE FUNCTION get_all_tickets(
  p_token      TEXT,
  p_phone      TEXT   DEFAULT NULL,
  p_ticket_no  TEXT   DEFAULT NULL,
  p_status     TEXT   DEFAULT NULL,
  p_service    TEXT   DEFAULT NULL
)
RETURNS SETOF tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM admin_check(p_token);
  RETURN QUERY
  SELECT * FROM tickets
  WHERE (p_phone     IS NULL OR phone      = p_phone)
    AND (p_ticket_no IS NULL OR ticket_no  = p_ticket_no)
    AND (p_status    IS NULL OR status     = p_status)
    AND (p_service   IS NULL OR service_type = p_service)
  ORDER BY created_at DESC
  LIMIT 300;
END;
$$;

-- 修改工单状态（管理员），可选写操作日志
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
  UPDATE tickets SET status = p_status, updated_at = now()
  WHERE ticket_no = p_ticket_no;
  IF p_note IS NOT NULL AND p_note <> '' THEN
    INSERT INTO operation_logs (ticket_id, action, details)
    SELECT id, 'status_change', p_note
    FROM tickets WHERE ticket_no = p_ticket_no;
  END IF;
END;
$$;

-- 授权 anon 调用（前端用 anon key 调用）
GRANT EXECUTE ON FUNCTION admin_login(TEXT)            TO anon;
GRANT EXECUTE ON FUNCTION admin_logout(TEXT)           TO anon;
GRANT EXECUTE ON FUNCTION admin_check(TEXT)            TO anon;
GRANT EXECUTE ON FUNCTION get_all_tickets(TEXT,TEXT,TEXT,TEXT,TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_update_ticket(TEXT,TEXT,TEXT,TEXT)   TO anon;

COMMENT ON TABLE site_config IS '站点配置：admin_pass_hash 为管理员口令 bcrypt 哈希';
