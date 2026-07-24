// supabase/functions/process-ticket/index.js
// Edge Function：处理新工单 —— 同步飞书多维表格 + 邮件通知
// 部署命令：supabase functions deploy process-ticket

import { createClient } from 'npm:@supabase/supabase-js@2'

// ── 环境变量（在 Supabase 控制台 Functions > Secrets 中配置）──
const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')
const SUPABASE_KEY       = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const FEISHU_APP_ID      = Deno.env.get('FEISHU_APP_ID')       // 飞书应用 App ID
const FEISHU_APP_SECRET  = Deno.env.get('FEISHU_APP_SECRET')   // 飞书应用 App Secret
const FEISHU_APP_TOKEN   = Deno.env.get('FEISHU_APP_TOKEN')    // 多维表格 app_token
const FEISHU_TABLE_ID    = Deno.env.get('FEISHU_TABLE_ID')     // 多维表格 table_id
const RESEND_API_KEY     = Deno.env.get('RESEND_API_KEY')      // Resend 邮件 API Key（可选）
const FROM_EMAIL         = Deno.env.get('FROM_EMAIL') || 'noreply@yourdomain.com'

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

// ── 服务类型映射 ──────────────────────────────────────────────
const SERVICE_TYPE_MAP = {
  package_change:  '套餐变更',
  broadband_open:  '开通宽带',
  broadband_close: '关闭宽带',
  query_account:   '查询账号',
  query_balance:   '查询余额',
  trouble_report:  '故障报修',
  cancel_account:  '账户销户',
}

// ── 主处理函数 ────────────────────────────────────────────────
Deno.serve(async (req) => {
  // CORS 预检
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
    const ticketData = await req.json()

    // 1. 数据验证
    const validation = validateTicketData(ticketData)
    if (!validation.valid) {
      return jsonResponse({ error: validation.message }, 400)
    }

    // 2. 从数据库获取已保存的工单（前端直接写入，这里只做后续处理）
    const { data: ticket, error: fetchErr } = await supabase
      .from('tickets')
      .select('*')
      .eq('ticket_no', ticketData.ticket_no)
      .single()

    // 如果前端没有直接写库（旧流程），在此写入
    let savedTicket = ticket
    if (fetchErr || !ticket) {
      const { data: inserted, error: insertErr } = await supabase
        .from('tickets')
        .insert([{
          ticket_no:         ticketData.ticket_no,
          phone:             ticketData.phone,
          name:              ticketData.name,
          id_card:           ticketData.id_card,
          student_no:        ticketData.student_no,
          service_type:      ticketData.service_type,
          description:       ticketData.description,
          package:           ticketData.package || null,
          id_card_front_url: ticketData.id_card_front_url || '',
          id_card_back_url:  ticketData.id_card_back_url || '',
          email:             ticketData.email || null,
          status:            'pending',
        }])
        .select()
        .single()

      if (insertErr) throw insertErr
      savedTicket = inserted
    }

    // 2.5 上传身份证图片到 Storage（service_role 权限，不受 RLS 限制）
    let frontUrl = savedTicket.id_card_front_url || ''
    let backUrl  = savedTicket.id_card_back_url  || ''
    const ts = Date.now()
    try {
      if (ticketData.id_card_front_base64 && !frontUrl) {
        frontUrl = await uploadBase64Image(savedTicket.ticket_no, ticketData.id_card_front_base64, `front-${ts}.jpg`)
      }
      if (ticketData.id_card_back_base64 && !backUrl) {
        backUrl  = await uploadBase64Image(savedTicket.ticket_no, ticketData.id_card_back_base64, `back-${ts}.jpg`)
      }
      // 更新工单中的图片 URL
      if (frontUrl || backUrl) {
        await supabase.from('tickets')
          .update({ id_card_front_url: frontUrl, id_card_back_url: backUrl })
          .eq('ticket_no', savedTicket.ticket_no)
        savedTicket.id_card_front_url = frontUrl
        savedTicket.id_card_back_url  = backUrl
      }
    } catch (uploadErr) {
      console.warn('图片上传失败（非阻断）:', uploadErr.message)
    }

    // 3. 同步到飞书多维表格（失败不阻断）
    let feishuRecordId = null
    if (FEISHU_APP_ID && FEISHU_APP_SECRET && FEISHU_APP_TOKEN && FEISHU_TABLE_ID) {
      try {
        const feishuResult = await syncToFeishu(savedTicket)
        feishuRecordId = feishuResult?.data?.record?.record_id
      } catch (feishuErr) {
        console.warn('飞书同步失败（非阻断）:', feishuErr.message)
      }
    }

    // 4. 发送邮件通知（如配置了邮箱）
    if (savedTicket.email && RESEND_API_KEY) {
      try {
        await sendEmailNotification(savedTicket)
      } catch (emailErr) {
        console.warn('邮件发送失败（非阻断）:', emailErr.message)
      }
    }

    // 5. 记录操作日志
    await supabase.from('operation_logs').insert([{
      ticket_id:  savedTicket.id,
      action:     'CREATE_TICKET',
      actor:      'system',
      details:    `工单创建成功，服务类型：${SERVICE_TYPE_MAP[savedTicket.service_type] || savedTicket.service_type}`,
      ip_address: req.headers.get('x-forwarded-for') || req.headers.get('cf-connecting-ip') || 'unknown',
    }])

    return jsonResponse({
      success:          true,
      ticket_no:        savedTicket.ticket_no,
      feishu_record_id: feishuRecordId,
    }, 200)

  } catch (err) {
    console.error('处理工单失败:', err)
    return jsonResponse({ error: '服务器内部错误', detail: err.message }, 500)
  }
})

// ── 数据验证 ──────────────────────────────────────────────────
function validateTicketData(data) {
  if (!data.ticket_no)    return { valid: false, message: '工单号不能为空' }
  if (!data.phone || !/^1[3-9]\d{9}$/.test(data.phone)) {
    return { valid: false, message: '手机号格式不正确' }
  }
  if (!data.name)         return { valid: false, message: '姓名不能为空' }
  if (!data.id_card || !/^\d{17}[\dXx]$/.test(data.id_card)) {
    return { valid: false, message: '身份证号格式不正确' }
  }
  if (!data.student_no)   return { valid: false, message: '学号不能为空' }
  if (!data.service_type) return { valid: false, message: '服务类型不能为空' }
  return { valid: true }
}

// ── 同步到飞书多维表格 ─────────────────────────────────────────
async function syncToFeishu(ticket) {
  const accessToken = await getFeishuAccessToken()

  const url = `https://open.feishu.cn/open-apis/bitable/v1/apps/${FEISHU_APP_TOKEN}/tables/${FEISHU_TABLE_ID}/records`

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      fields: {
        '工单号':     ticket.ticket_no,
        '手机号':     ticket.phone,
        '姓名':       ticket.name,
        '身份证号':   maskIdCard(ticket.id_card),
        '学号':       ticket.student_no,
        '需求类型':   SERVICE_TYPE_MAP[ticket.service_type] || ticket.service_type,
        '需求描述':   ticket.description || '',
        '套餐':       ticket.package || '',
        '状态':       '待处理',
        '提交时间':   new Date(ticket.created_at).getTime(),  // 飞书日期字段需要毫秒时间戳
        // 身份证附件字段需要先上传到飞书再引用，此处放 URL 供参考
        '身份证正面链接': ticket.id_card_front_url || '',
        '身份证反面链接': ticket.id_card_back_url  || '',
      },
    }),
  })

  const result = await response.json()
  if (result.code !== 0) {
    throw new Error(`飞书API错误: ${result.msg}`)
  }
  return result
}

// ── 获取飞书 Tenant Access Token ──────────────────────────────
async function getFeishuAccessToken() {
  const response = await fetch('https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ app_id: FEISHU_APP_ID, app_secret: FEISHU_APP_SECRET }),
  })
  const data = await response.json()
  if (!data.tenant_access_token) throw new Error('获取飞书Token失败')
  return data.tenant_access_token
}

// ── 身份证号脱敏 ──────────────────────────────────────────────
function maskIdCard(idCard) {
  if (!idCard || idCard.length < 15) return idCard
  return `${idCard.substring(0, 6)}********${idCard.substring(14)}`
}

// ── 邮件通知（使用 Resend）────────────────────────────────────
async function sendEmailNotification(ticket) {
  const serviceLabel = SERVICE_TYPE_MAP[ticket.service_type] || ticket.service_type

  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px">
      <div style="background:linear-gradient(135deg,#722ed1,#531dab);border-radius:12px;padding:20px;color:#fff;text-align:center;margin-bottom:20px">
        <h1 style="margin:0;font-size:20px">📡 校园网服务申请已受理</h1>
        <p style="margin:8px 0 0;opacity:.85;font-size:13px">浙江海洋大学 · 联通校园网服务中心</p>
      </div>
      <p>您好，<strong>${ticket.name}</strong>，您的服务申请已成功提交。</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        <tr style="border-bottom:1px solid #f0f0f0"><td style="padding:10px 0;color:#999">工单号</td><td style="font-weight:bold;color:#722ed1">${ticket.ticket_no}</td></tr>
        <tr style="border-bottom:1px solid #f0f0f0"><td style="padding:10px 0;color:#999">服务类型</td><td>${serviceLabel}</td></tr>
        <tr style="border-bottom:1px solid #f0f0f0"><td style="padding:10px 0;color:#999">需求描述</td><td>${ticket.description || '—'}</td></tr>
        <tr><td style="padding:10px 0;color:#999">提交时间</td><td>${new Date(ticket.created_at).toLocaleString('zh-CN')}</td></tr>
      </table>
      <div style="background:#f9f0ff;border:1px solid #d3adf7;border-radius:8px;padding:14px;margin-top:16px;font-size:13px;color:#531dab">
        ⏰ 预计 <strong>2小时内</strong> 处理完毕，如有进展我们会再次通知您。
      </div>
      <p style="font-size:12px;color:#ccc;margin-top:20px;text-align:center">
        此邮件由系统自动发送，请勿回复
      </p>
    </div>
  `

  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from:    FROM_EMAIL,
      to:      [ticket.email],
      subject: `【校园网服务】您的工单 ${ticket.ticket_no} 已受理`,
      html,
    }),
  })
}

// ── 上传 base64 图片到 Storage（service_role 权限，绕过 RLS）──
async function uploadBase64Image(ticketNo, base64Str, filename) {
  // 解析 data:image/jpeg;base64,xxxx 格式
  const matches = base64Str.match(/^data:(image\/\w+);base64,(.+)$/)
  if (!matches) throw new Error('无效的 base64 图片格式')
  const mimeType = matches[1]
  const base64Data = matches[2]

  // 解码为二进制
  const binaryStr = atob(base64Data)
  const bytes = new Uint8Array(binaryStr.length)
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i)
  }
  const blob = new Blob([bytes], { type: mimeType })

  const path = `${ticketNo}/${filename}`
  const { data, error } = await supabase.storage
    .from('id-cards')
    .upload(path, blob, { contentType: mimeType, upsert: true })

  if (error) throw error

  const { data: urlData } = supabase.storage.from('id-cards').getPublicUrl(data.path)
  return urlData.publicUrl
}

// ── 辅助：JSON 响应 ───────────────────────────────────────────
function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type':                'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  })
}
