-- ============================================================================
-- 需求描述图片附件支持
-- 背景：用户端希望在「需求描述」中上传截图（故障图、页面提示等），
--       便于管理员快速定位问题。原 submit_ticket 仅支持身份证正反面。
-- 做法：tickets 增加 desc_images text[] 列（仅存 Storage 路径，非 PII，明文即可）；
--       submit_ticket 增加 p_desc_images 参数并写库。复用 id-cards 私有桶
--       （desc- 前缀），避免新建桶与额外的 RLS 配置。
-- 用法：Supabase Studio > SQL Editor 全选执行（幂等，可重复跑）。
--       执行后平台会触发 PostgREST 缓存重载。
-- 注意：get_all_tickets 返回 SETOF tickets，新增列会自动包含，无需改动。
-- ============================================================================

-- 1) 新增 desc_images 列
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS desc_images text[] DEFAULT '{}';

-- 2) 重建 submit_ticket，增加 p_desc_images 参数
--    先 DROP 旧签名（11 text + boolean），避免重载产生歧义
DROP FUNCTION IF EXISTS submit_ticket(
  text, text, text, text, text, text, text, text, text, text, text, boolean
);

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
  p_desc_images   text[] DEFAULT NULL,
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

  -- 插入（status 强制 pending；desc_images 可选）
  INSERT INTO tickets (
    ticket_no, phone, name, id_card, student_no, service_type,
    description, package, email, id_card_front_url, id_card_back_url, desc_images, status
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
    COALESCE(p_desc_images, '{}'),
    'pending'
  );

  RETURN p_ticket_no;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_ticket_no';
END;
$$;

GRANT EXECUTE ON FUNCTION submit_ticket(
  text, text, text, text, text, text, text, text, text, text, text, text[], boolean
) TO anon;

-- 校验：确认新列与函数已就绪
SELECT
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name='tickets' AND column_name='desc_images') AS has_column,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='submit_ticket') AS func_overloads;
