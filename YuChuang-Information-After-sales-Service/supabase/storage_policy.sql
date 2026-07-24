-- ============================================================================
-- 修复身份证照片上传/查看不可用的问题（功能可靠性）
-- 现象：用户端上传身份证照片被 RLS 拒绝（new row violates row-level security
--       policy），且管理员端看不到照片。根因是 id-cards 桶缺少 anon 读写策略。
-- 用法：在 Supabase Studio > SQL Editor 全选执行本文件（幂等，可重复执行）。
-- ============================================================================

-- 1) 创建私有桶（身份证属敏感 PII，必须私有，通过签名 URL 访问）
insert into storage.buckets (id, name, public)
values ('id-cards', 'id-cards', false)
on conflict (id) do nothing;

-- 2) 允许匿名写入（用户端直传身份证照片）
drop policy if exists "anon_upload_id_cards" on storage.objects;
create policy "anon_upload_id_cards"
  on storage.objects
  for insert
  to anon
  with check ( bucket_id = 'id-cards' );

-- 3) 允许匿名读取（管理员端生成签名 URL 查看照片时，底层需 SELECT）
drop policy if exists "anon_read_id_cards" on storage.objects;
create policy "anon_read_id_cards"
  on storage.objects
  for select
  to anon
  using ( bucket_id = 'id-cards' );

-- 校验
select 'bucket_exists' as check_item,
       exists(select 1 from storage.buckets where id='id-cards') as ok;
