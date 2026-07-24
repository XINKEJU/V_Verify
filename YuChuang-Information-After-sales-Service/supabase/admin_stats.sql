-- ============================================================
--  管理后台数据看板：聚合统计
--  幂等，可重复执行。需在 Supabase Studio > SQL Editor 全选执行一次。
--  说明：本环境对 Supabase 直连库被 DNS 拦截、Management API 被 Cloudflare
--        封禁，无法自动建对象；经 Studio 执行会走管理通道并正确重载 PostgREST。
--  安全：仅返回聚合计数，不含任何 PII（身份证/手机号等），故授权 anon 调用。
-- ============================================================
create or replace function get_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total       int;
  v_today       int;
  v_pending     int;
  v_processing  int;
  v_dispatched  int;
  v_completed   int;
  v_closed      int;
  v_resolved    int;
  v_avg_hours   numeric;
  v_by_service  jsonb;
  v_by_status   jsonb;
  v_trend       jsonb;
begin
  select count(*) into v_total from tickets;

  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'processing'),
    count(*) filter (where status = 'dispatched'),
    count(*) filter (where status = 'completed'),
    count(*) filter (where status = 'closed')
  into v_pending, v_processing, v_dispatched, v_completed, v_closed
  from tickets;

  select count(*) into v_today
  from tickets where created_at >= current_date;

  select count(*) into v_resolved
  from tickets where status in ('completed', 'closed');

  -- 已解决工单的平均处理时长（小时）：completed_at - created_at
  select coalesce(
    avg(extract(epoch from (coalesce(completed_at, now()) - created_at)) / 3600.0), 0)
  into v_avg_hours
  from tickets
  where status in ('completed', 'closed') and completed_at is not null;

  -- 各服务类型工单量
  select coalesce(jsonb_object_agg(service_type, cnt), '{}'::jsonb)
  into v_by_service
  from (
    select service_type, count(*)::int as cnt
    from tickets group by service_type
  ) s;

  -- 状态分布
  v_by_status := jsonb_build_object(
    'pending',     v_pending,
    'processing',  v_processing,
    'dispatched',  v_dispatched,
    'completed',   v_completed,
    'closed',      v_closed
  );

  -- 近 7 日（含今日）每日提交量
  select coalesce(
    jsonb_agg(jsonb_build_object('day', d, 'cnt', coalesce(c, 0))
      order by d),
    '[]'::jsonb)
  into v_trend
  from (
    select to_char(g.d, 'MM-DD') as d,
           (select count(*)::int from tickets t where t.created_at::date = g.d) as c
    from generate_series(current_date - 6, current_date, interval '1 day') g(d)
  ) t;

  return jsonb_build_object(
    'total',      v_total,
    'today',      v_today,
    'by_status',  v_by_status,
    'resolved',   v_resolved,
    'avg_hours',  round(v_avg_hours, 1),
    'by_service', v_by_service,
    'trend',      v_trend
  );
end;
$$;

grant execute on function get_dashboard_stats() to anon;
