// supabase/functions/query-ticket/index.js
// Edge Function：学生查询自己的工单
// 部署命令：supabase functions deploy query-ticket

import { createClient } from 'npm:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

const SERVICE_TYPE_MAP = {
  package_change:  '套餐变更',
  broadband_open:  '开通宽带',
  broadband_close: '关闭宽带',
  query_account:   '查询账号',
  query_balance:   '查询余额',
  trouble_report:  '故障报修',
  cancel_account:  '账户销户',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: '仅支持 POST 请求' }, 405)
  }

  try {
    const { phone, ticket_no } = await req.json()

    if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
      return jsonResponse({ error: '手机号格式不正确' }, 400)
    }

    let query = supabase
      .from('tickets')
      .select('id, ticket_no, service_type, description, package, status, result, created_at, completed_at')
      .eq('phone', phone)
      .order('created_at', { ascending: false })
      .limit(20)

    if (ticket_no?.trim()) {
      query = query.eq('ticket_no', ticket_no.trim().toUpperCase())
    }

    const { data, error } = await query
    if (error) throw error

    // 返回时对服务类型做映射，隐藏身份证等敏感字段
    const tickets = (data || []).map(t => ({
      ...t,
      service_type_label: SERVICE_TYPE_MAP[t.service_type] || t.service_type,
    }))

    return jsonResponse({ success: true, tickets }, 200)

  } catch (err) {
    console.error('查询工单失败:', err)
    return jsonResponse({ error: '查询失败，请稍后重试' }, 500)
  }
})

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type':                'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  })
}
