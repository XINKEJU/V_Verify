-- ============================================================
-- 修复：tickets 表匿名 INSERT 策略（P0 功能故障修复）
-- 问题：此前安全加固误删了 anon_insert_ticket 策略，导致用户端
--       提交工单被 RLS 拦截（new row violates row-level security policy）。
-- 解决：重建匿名插入策略，并加固为「仅允许提交 pending 且不可伪造处理结果」。
-- 在 Supabase 控制台 > SQL Editor 全选执行（幂等，可重复跑）。
-- ============================================================

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

-- 确认策略已生效（可选查看）
-- SELECT policyname, cmd, roles, with_check FROM pg_policies
-- WHERE schemaname='public' AND tablename='tickets' AND cmd='INSERT';
