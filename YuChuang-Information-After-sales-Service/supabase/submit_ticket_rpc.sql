-- ============================================================
-- 修复提交功能（P0）：引入服务端 submit_ticket 存储过程
-- ============================================================
-- 背景：tickets 表的匿名 INSERT 策略是经 pg8000 直连写入的，
--       未能触发 PostgREST 策略缓存重载，导致匿名提交与
--       管理员代客建单均被 RLS 拦截（42501 / new row violates RLS）。
-- 方案：提交统一走 SECURITY DEFINER 存储过程，由函数所有者
--       （postgres）直写，绕过 RLS，从根本上摆脱对匿名 INSERT
--       策略缓存的依赖。
-- 用法：在 Supabase 控制台 > SQL Editor 全选执行（幂等，可重复跑）。
--       执行后平台会触发 PostgREST 缓存重载，submit_ticket 即可经
--       REST 被前端调用。
-- ============================================================

-- 1) 允许管理员代客建单时留空身份证/学号（用户端仍由前端强制必填）
ALTER TABLE tickets ALTER COLUMN id_card DROP NOT NULL;
ALTER TABLE tickets ALTER COLUMN student_no DROP NOT NULL;

-- 2) 重建匿名 INSERT 策略（防御性兜底；即使不走直插，也保证策略存在）
DROP POLICY IF EXISTS anon_insert_ticket ON tickets;
CREATE POLICY "anon_insert_ticket" ON tickets
  FOR INSERT TO anon
  WITH CHECK (
    status = 'pending'
    AND result IS NULL
    AND assigned_to IS NULL
    AND handled_by IS NULL
    AND completed_at IS NULL
  );

-- 3) 提交存储过程（SECURITY DEFINER，服务端校验，强制 pending）
CREATE OR REPLACE FUNCTION submit_ticket(
  p_ticket_no     text,
  p_phone         text,
  p_name          text,
  p_id_card       text,
  p_student_no    text,
  p_service_type  text,
  p_description   text,
  p_package       text DEFAULT NULL,
  p_email         text DEFAULT NULL,
  p_front         text DEFAULT NULL,
  p_back          text DEFAULT NULL,
  p_throttle      boolean DEFAULT true
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_dup boolean;
BEGIN
  -- 输入校验
  IF p_ticket_no IS NULL OR p_ticket_no !~ '^GY-\d{8}-[A-Z0-9]{9}$' THEN
    RAISE EXCEPTION 'invalid_ticket_no';
  END IF;
  IF p_phone IS NULL OR p_phone !~ '^1[3-9]\d{9}$' THEN
    RAISE EXCEPTION 'invalid_phone';
  END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;
  IF p_service_type IS NULL OR p_service_type NOT IN
     ('package_change','broadband_open','broadband_close','query_account','trouble_report','cancel_account') THEN
    RAISE EXCEPTION 'invalid_service_type';
  END IF;
  IF p_description IS NULL OR length(trim(p_description)) = 0 THEN
    RAISE EXCEPTION 'invalid_description';
  END IF;

  -- 频率限制（用户端启用；管理员代客提交跳过）
  IF p_throttle THEN
    IF (SELECT NOT check_submit_allowed(p_phone)) THEN
      RAISE EXCEPTION 'too_frequent';
    END IF;
  END IF;

  -- 去重（唯一约束兜底）
  SELECT EXISTS(SELECT 1 FROM tickets WHERE ticket_no = p_ticket_no) INTO v_dup;
  IF v_dup THEN
    RAISE EXCEPTION 'duplicate_ticket_no';
  END IF;

  -- 插入（status 强制 pending；禁止客户端赋值结果/处理人/完成时间）
  INSERT INTO tickets (
    ticket_no, phone, name, id_card, student_no, service_type,
    description, package, email, id_card_front_url, id_card_back_url, status
  ) VALUES (
    p_ticket_no,
    p_phone,
    trim(p_name),
    NULLIF(trim(p_id_card), ''),
    NULLIF(trim(p_student_no), ''),
    p_service_type,
    trim(p_description),
    NULLIF(trim(p_package), ''),
    NULLIF(trim(p_email), ''),
    NULLIF(p_front, ''),
    NULLIF(p_back, ''),
    'pending'
  );

  RETURN p_ticket_no;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_ticket_no';
END;
$$;

GRANT EXECUTE ON FUNCTION submit_ticket(
  text, text, text, text, text, text, text, text, text, text, text, boolean
) TO anon;
