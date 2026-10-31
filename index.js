/**
 * dsh-pocket — a pocket-sized, iPhone-first surface for DeepSeek Harness.
 *
 * The phone reaches this Host over your own Tailscale tailnet (or `tailscale
 * serve`), loads a small standalone web app from `/pocket`, and talks to the
 * Session Controller through the JSON routes below. Nothing is exposed to the
 * public internet and nothing outside the taillnet can login: every request
 * needs the pairing token minted into `$DSH_HOME/pocket/state.json`.
 *
 *   iPhone --Tailscale--> webServer(/pocket/*) --> sessionController
 *
 * The UI itself is a static PWA in ./web — no build step, no framework.
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-pocket'
export const inject = ['webServer', 'sessionController', 'agents', 'sessions']

const PREFIX = '/pocket'
const WEB_DIR = fileURLToPath(new URL('./web/', import.meta.url))
const COOKIE = 'pocket_key'
const MAX_ITEMS = 600
const FEED_IDLE_MS = 15 * 60 * 1000
const VERSION = '1.0.0'

const log = (ctx, level, message) => {
  try {
    const logger = ctx && ctx.logger
    if (logger && typeof logger[level] === 'function') logger[level](`[dsh-pocket] ${message}`)
  } catch {
    /* logging must never break the route */
  }
}

/* ------------------------------------------------------------------ state */

function homeDir() {
  return process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
}

function stateFile() {
  return path.join(homeDir(), 'pocket', 'state.json')
}

function loadState() {
  try {
    const raw = fs.readFileSync(stateFile(), 'utf8')
    const parsed = JSON.parse(raw)
    if (parsed && typeof parsed.token === 'string' && parsed.token.length >= 16) {
      if (!('totp' in parsed)) parsed.totp = null
      if (!parsed.devices || typeof parsed.devices !== 'object') parsed.devices = {}
      return parsed
    }
  } catch {
    /* first run or unreadable: mint below */
  }
  const state = { token: crypto.randomBytes(24).toString('hex'), createdAt: Date.now() }
  try {
    fs.mkdirSync(path.dirname(stateFile()), { recursive: true, mode: 0o700 })
    fs.writeFileSync(stateFile(), JSON.stringify(state, null, 2), { mode: 0o600 })
  } catch (error) {
    log({}, 'warn', `cannot persist pairing token: ${String(error)}`)
  }
  return state
}

function saveState(state) {
  try {
    fs.mkdirSync(path.dirname(stateFile()), { recursive: true, mode: 0o700 })
    fs.writeFileSync(stateFile(), JSON.stringify(state, null, 2), { mode: 0o600 })
  } catch {
    /* best effort */
  }
}

function tokenDigest(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex')
}

function safeEqual(a, b) {
  const left = Buffer.from(String(a))
  const right = Buffer.from(String(b))
  if (left.length !== right.length) return false
  return crypto.timingSafeEqual(left, right)
}

/* ------------------------------------------------------------- event model */

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8'
}

const TOOL_LABELS = {
  bash: '运行命令',
  pwsh: '运行命令',
  read: '读取文件',
  read_image: '查看图片',
  apply_patch: '应用补丁',
  list: '列出目录',
  shell: '运行命令',
  write: '写入文件',
  edit: '修改文件',
  glob: '查找文件',
  grep: '搜索内容',
  ls: '列出目录',
  web_search: '网页搜索',
  web_fetch: '读取网页',
  task: '委派子任务',
  skill: '调用技能',
  todo_write: '更新待办',
  exit_plan_mode: '提交计划',
  ask_user_question: '向你提问',
  present: '交付文件',
  workflow: '编排工作流',
  subagent: '子任务',
  subagent_fork: '子任务',
  schedule_create: '创建提醒',
  goal: '目标'
}

function parseAsk(raw) {
  let value
  try {
    value = typeof raw === 'string' ? JSON.parse(raw) : raw
  } catch {
    return null
  }
  const list = value && Array.isArray(value.questions) ? value.questions : []
  if (list.length === 0) return null
  return {
    questions: list.slice(0, 4).map((question) => ({
      header: typeof question.header === 'string' ? question.header : '',
      question: typeof question.question === 'string' ? question.question : '',
      multiSelect: question.multiSelect === true,
      options: Array.isArray(question.options)
        ? question.options.slice(0, 8).map((option) => ({
            label: typeof option.label === 'string' ? option.label : '',
            description: typeof option.description === 'string' ? option.description : ''
          }))
        : []
    }))
  }
}

function textOfContent(content) {
  if (!Array.isArray(content)) return ''
  const out = []
  for (const block of content) {
    if (block && block.type === 'text' && typeof block.text === 'string') out.push(block.text)
  }
  return out.join('')
}

function reasoningOfContent(content) {
  if (!Array.isArray(content)) return ''
  const out = []
  for (const block of content) {
    if (block && block.type === 'reasoning' && typeof block.text === 'string') out.push(block.text)
  }
  return out.join('')
}

function imagesOfContent(content) {
  if (!Array.isArray(content)) return []
  const out = []
  for (const block of content) {
    if (block && block.type === 'image') {
      const ref = block.attachment && typeof block.attachment === 'object' ? block.attachment : block
      out.push({
        mediaType: String(ref.mediaType || 'image/*'),
        name: typeof ref.name === 'string' ? ref.name : '',
        ...(typeof ref.attachmentId === 'string' ? { attachmentId: ref.attachmentId } : {})
      })
    }
  }
  return out
}

function textFromStream(records) {
  if (!Array.isArray(records)) return ''
  const out = []
  for (const record of records) {
    if (!record || typeof record !== 'object') continue
    if (record.type === 'text-chunks' && Array.isArray(record.texts)) out.push(record.texts.join(''))
    else if (record.type === 'chunk' && record.chunk && record.chunk.type === 'text-delta' && typeof record.chunk.text === 'string') out.push(record.chunk.text)
  }
  return out.join('')
}

function oneLine(text, limit) {
  const flat = String(text || '').replace(/\s+/g, ' ').trim()
  return flat.length > limit ? `${flat.slice(0, limit - 1)}…` : flat
}

function toolDetail(name, argsRaw) {
  let args
  try {
    args = typeof argsRaw === 'string' ? JSON.parse(argsRaw) : argsRaw
  } catch {
    return oneLine(argsRaw, 120)
  }
  if (!args || typeof args !== 'object') return oneLine(argsRaw, 120)
  const pick = args.command ?? args.file_path ?? args.path ?? args.pattern ?? args.query ?? args.url ?? args.description ?? args.prompt
  return oneLine(typeof pick === 'string' ? pick : JSON.stringify(args), 140)
}

function toolResultText(data) {
  const message = data && data.message
  const content = message && Array.isArray(message.content) ? message.content : []
  const text = textOfContent(content)
  if (text) return text
  if (data && data.error && (data.error.message || data.error.name)) return String(data.error.message || data.error.name)
  return ''
}

/* ------------------------------------------------------------------- feeds */

class Feed {
  constructor(ctx, sessionId) {
    this.ctx = ctx
    this.sessionId = sessionId
    this.items = []
    this.byId = new Map()
    this.rev = 0
    this.cursor = -1
    this.hasMore = false
    this.running = false
    this.live = { text: '', think: '' }
    this.title = ''
    this.lastUsed = Date.now()
    this.stepStart = null
    this.context = null
    this.contextAt = 0
    this.controller = null
    this.started = false
    this.oldestSeq = null
  }

  start() {
    if (this.started) return
    this.started = true
    const controller = new AbortController()
    this.controller = controller
    this.loop(controller, 0)
  }

  stop() {
    this.started = false
    if (this.controller) this.controller.abort()
    this.controller = null
  }

  touch() {
    this.lastUsed = Date.now()
  }

  async loop(controller, attempt) {
    let ended = false
    try {
      const stream = this.ctx.sessionController.follow(
        { address: { kind: 'session', sessionId: this.sessionId }, assistantStream: true, maxMessages: 60 },
        controller.signal
      )
      for await (const frame of stream) {
        if (controller.signal.aborted) return
        this.onFrame(frame)
      }
      ended = true
    } catch (error) {
      if (!controller.signal.aborted) log(this.ctx, 'warn', `follow ${this.sessionId} failed: ${String(error && error.message || error)}`)
    }
    if (controller.signal.aborted || this.controller !== controller) return
    if (Date.now() - this.lastUsed > FEED_IDLE_MS) {
      this.started = false
      return
    }
    if (attempt >= 30) {
      log(this.ctx, 'warn', `follow ${this.sessionId} gave up after ${attempt} attempts`)
      this.started = false
      return
    }
    const wait = Math.min(300 * (attempt + 1), 2500)
    const timer = setTimeout(() => {
      if (controller.signal.aborted || this.controller !== controller) return
      if (ended) log(this.ctx, 'info', `follow ${this.sessionId} reconnecting`)
      this.loop(controller, attempt + 1)
    }, wait)
    if (typeof timer.unref === 'function') timer.unref()
  }

  onFrame(frame) {
    if (!frame || typeof frame !== 'object') return
    if (process.env.DSH_POCKET_DEBUG === '1') {
      try {
        fs.appendFileSync('/tmp/pocket-frames.jsonl', `${JSON.stringify(frame)}\n`)
      } catch {
        /* debug only */
      }
    }
    this.touch()
    if (frame.type === 'snapshot') {
      const records = Array.isArray(frame.records) ? frame.records : []
      let first = null
      let lastStart = -1
      let lastEnd = -1
      for (const record of records) {
        if (!record || record.type !== 'event' || !record.event) continue
        const event = record.event
        if (first === null) first = event.seq
        if (event.type === 'turn/start') lastStart = Math.max(lastStart, event.seq)
        if (event.type === 'turn/end') lastEnd = Math.max(lastEnd, event.seq)
        this.ingest(event)
      }
      if (lastStart > lastEnd) this.running = true
      if (typeof frame.cursor === 'number') this.cursor = Math.max(this.cursor, frame.cursor)
      if (first !== null) this.oldestSeq = this.oldestSeq === null ? first : Math.min(this.oldestSeq, first)
      if (this.items.length === 0) this.hasMore = frame.hasMore === true
      return
    }
    if (frame.type === 'assistant-stream') {
      const inner = frame.frame
      if (!inner || inner.type !== 'chunk' || !inner.chunk) return
      const chunk = inner.chunk
      if (chunk.type === 'text-delta' && typeof chunk.text === 'string') {
        this.live.text += chunk.text
        this.rev += 1
        return
      }
      if (chunk.type === 'reasoning-delta' && typeof chunk.text === 'string') {
        this.live.think += chunk.text
        this.rev += 1
        return
      }
      return
    }
    if (frame.type === 'event' && frame.event) this.ingest(frame.event)
  }

  upsert(item) {
    const existing = this.byId.get(item.id)
    if (existing) {
      Object.assign(existing, item)
      existing.rev = ++this.rev
      return existing
    }
    item.rev = ++this.rev
    this.byId.set(item.id, item)
    this.items.push(item)
    this.items.sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0))
    if (this.items.length > MAX_ITEMS) {
      const dropped = this.items.splice(0, this.items.length - MAX_ITEMS)
      for (const gone of dropped) this.byId.delete(gone.id)
    }
    return item
  }

  ingest(event) {
    const seq = typeof event.seq === 'number' ? event.seq : -1
    if (seq >= 0) this.cursor = Math.max(this.cursor, seq)
    const data = event.data || {}
    const time = typeof event.time === 'number' ? event.time : Date.now()

    switch (event.type) {
      case 'user/message': {
        const source = data.source
        if (!source || source.kind !== 'user') return
        if (event.surfaceOp === 'remove') return
        const text = textOfContent(data.content)
        const imgs = imagesOfContent(data.content)
        this.upsert({ id: `e${seq}`, k: 'u', seq, t: time, text, imgs })
        return
      }
      case 'assistant/message': {
        const message = data.message || {}
        const blocks = Array.isArray(message.content) ? message.content : []
        const text = textFromStream(data.stream) || textOfContent(blocks)
        const think = reasoningOfContent(blocks)
        if (!text && !think) return
        this.live = { text: '', think: '' }
        const item = { id: `e${seq}`, k: 'a', seq, t: time, text, think }
        const usage = data.usage
        if (usage && typeof usage === 'object') {
          const input = Number(usage.inputTokens) || 0
          const output = Number(usage.outputTokens) || 0
          const cacheRead = Number(usage.cacheReadTokens) || 0
          const cacheWrite = Number(usage.cacheWriteTokens) || 0
          const start = this.stepStart || time
          const secs = Math.max(0.001, (time - start) / 1000)
          item.usage = {
            input,
            output,
            cacheRead,
            cacheWrite,
            total: Number(usage.totalTokens) || input + output + cacheRead + cacheWrite,
            secs: Math.round(secs * 10) / 10,
            tps: output > 0 ? Math.round((output / secs) * 10) / 10 : null,
            cacheRate: input + cacheRead > 0 ? Math.round((cacheRead / (input + cacheRead)) * 1000) / 10 : null
          }
        }
        this.upsert(item)
        return
      }
      case 'tool/call': {
        const callId = String(data.callId || `c${seq}`)
        const toolName = String(data.name || 'tool')
        const item = {
          id: `c${callId}`,
          k: 't',
          seq,
          t: time,
          callId,
          name: toolName,
          label: TOOL_LABELS[toolName] || toolName,
          detail: toolDetail(toolName, data.arguments),
          status: 'run',
          result: '',
          isError: false
        }
        if (toolName === 'ask_user_question') {
          item.ask = parseAsk(data.arguments)
          item.detail = ''
        }
        this.upsert(item)
        return
      }
      case 'tool/result': {
        const message = data.message || {}
        const callId = String(message.toolCallId || data.callId || '')
        const item = this.byId.get(`c${callId}`)
        if (!item) return
        item.status = message.isError === true || data.error ? 'err' : 'ok'
        item.result = oneLine(toolResultText(data), 1200)
        item.rev = ++this.rev
        return
      }
      case 'turn/start': {
        this.running = true
        this.live = { text: '', think: '' }
        this.stepStart = time
        this.rev += 1
        return
      }
      case 'step/start': {
        this.stepStart = time
        return
      }
      case 'turn/end': {
        if (this.live.text.trim()) {
          this.upsert({ id: `live${seq}`, k: 'a', seq: seq + 0.5, t: time, text: this.live.text, think: this.live.think })
        }
        const reason = data.reason
        const kind = reason && typeof reason === 'object' ? reason.kind : undefined
        if (kind === 'error' || kind === 'blocked' || kind === 'aborted') {
          const failure = reason && reason.error
          const detail =
            (failure && (failure.message || failure.code)) ||
            (kind === 'aborted' ? '本轮已停止' : kind === 'blocked' ? '本轮被阻塞' : '模型或工具出错')
          this.upsert({ id: `n${seq}`, k: 'n', seq, t: time, text: String(detail) })
        }
        this.running = false
        this.live = { text: '', think: '' }
        this.rev += 1
        return
      }
      case 'approval/asked': {
        this.upsert({ id: `e${seq}`, k: 'n', seq, t: time, text: '需要你确认一项权限 — 请回到电脑上处理' })
        return
      }
      case 'approval/decided': {
        return
      }
      case 'session/title': {
        if (typeof data.title === 'string' && data.title.trim()) this.title = data.title.trim()
        return
      }
      default:
        return
    }
  }

  changedSince(rev) {
    if (!Number.isFinite(rev) || rev < 0 || rev > this.rev) return this.items.slice()
    if (this.rev - rev > 400) return this.items.slice()
    return this.items.filter((item) => item.rev > rev)
  }

  view() {
    const oldest = this.items.length ? this.items[0].seq : null
    return {
      ok: true,
      session: { id: this.sessionId, title: this.title },
      rev: this.rev,
      running: this.running,
      live: this.live,
      hasMore: this.hasMore && this.items.length === 0 ? true : this.hasMore,
      oldestSeq: typeof oldest === 'number' ? Math.floor(oldest) : null,
      context: this.context,
      items: this.items.map(({ rev, ...rest }) => rest)
    }
  }
}

/* --------------------------------------------------------------------- TOTP */

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

function base32Encode(buffer) {
  let bits = 0
  let value = 0
  let out = ''
  for (const byte of buffer) {
    value = (value << 8) | byte
    bits += 8
    while (bits >= 5) {
      out += BASE32[(value >>> (bits - 5)) & 31]
      bits -= 5
    }
  }
  if (bits > 0) out += BASE32[(value << (5 - bits)) & 31]
  return out
}

function base32Decode(text) {
  const clean = String(text).toUpperCase().replace(/[^A-Z2-7]/g, '')
  let bits = 0
  let value = 0
  const out = []
  for (const char of clean) {
    const index = BASE32.indexOf(char)
    if (index < 0) continue
    value = (value << 5) | index
    bits += 5
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff)
      bits -= 8
    }
  }
  return Buffer.from(out)
}

function totpAt(secret, step) {
  const key = base32Decode(secret)
  const counter = Buffer.alloc(8)
  counter.writeBigUInt64BE(BigInt(step))
  const digest = crypto.createHmac('sha1', key).update(counter).digest()
  const offset = digest[digest.length - 1] & 0x0f
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff)
  return String(binary % 1_000_000).padStart(6, '0')
}

function verifyTotp(secret, code) {
  const input = String(code || '').replace(/\s/g, '')
  if (!/^\d{6}$/.test(input)) return false
  const step = Math.floor(Date.now() / 30_000)
  for (let delta = -1; delta <= 1; delta += 1) {
    if (safeEqual(totpAt(secret, step + delta), input)) return true
  }
  return false
}

function hiddenFile() {
  return path.join(homeDir(), 'pocket', 'hidden.json')
}

function loadHidden() {
  try {
    const parsed = JSON.parse(fs.readFileSync(hiddenFile(), 'utf8'))
    return new Set(Array.isArray(parsed.ids) ? parsed.ids : [])
  } catch {
    return new Set()
  }
}

function saveHidden(ids) {
  try {
    fs.mkdirSync(path.dirname(hiddenFile()), { recursive: true, mode: 0o700 })
    fs.writeFileSync(hiddenFile(), JSON.stringify({ ids: [...ids] }, null, 2), { mode: 0o600 })
  } catch {
    /* best effort */
  }
}

function deviceKey(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex')
}

function mintDevice(state, label, publicKey) {
  const token = crypto.randomBytes(24).toString('hex')
  const id = crypto.randomBytes(12).toString('hex')
  state.devices[id] = {
    label: String(label || 'device').slice(0, 40),
    createdAt: Date.now(),
    lastSeen: Date.now(),
    tokenHash: tokenDigest(token),
    ...(publicKey ? { publicKey } : {})
  }
  return { id, token }
}

function deviceByToken(state, token) {
  if (!token) return null
  const hash = tokenDigest(token)
  for (const [id, device] of Object.entries(state.devices)) {
    if (device && device.tokenHash === hash) return { id, device }
  }
  return null
}

/* ------------------------------------------------------------------ routes */

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let size = 0
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > limit) {
        reject(Object.assign(new Error('request body too large'), { status: 413 }))
        req.destroy()
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8')
        resolve(raw ? JSON.parse(raw) : {})
      } catch (error) {
        reject(Object.assign(new Error('invalid JSON body'), { status: 400 }))
      }
    })
    req.on('error', reject)
  })
}

function sendJson(res, status, value) {
  const body = JSON.stringify(value)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(body)
  })
  res.end(body)
}

function sendFile(res, file, status = 200) {
  let data
  try {
    data = fs.readFileSync(file)
  } catch {
    sendJson(res, 404, { ok: false, error: 'not found' })
    return
  }
  const ext = path.extname(file).toLowerCase()
  res.writeHead(status, {
    'content-type': MIME[ext] || 'application/octet-stream',
    'content-length': data.length,
    'cache-control': 'no-store'
  })
  res.end(data)
}

function sessionLogExists(sessionId) {
  const root = path.join(homeDir(), 'sessions')
  try {
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue
      if (fs.existsSync(path.join(root, entry.name, sessionId, 'session.v4.jsonl.zstd'))) return true
    }
  } catch {
    /* unreadable sessions dir: treat as unknown */
    return true
  }
  return false
}

function sessionTitle(summary) {
  if (!summary || typeof summary !== 'object') return '会话'
  if (summary.blank === true) return '新会话'
  const projections = summary.projections
  const title = (projections && projections.values && projections.values.title) || summary.title
  if (typeof title === 'string' && title.trim()) return title.trim()
  if (typeof summary.cwd === 'string' && summary.cwd) {
    const parts = summary.cwd.split(/[\\/]/).filter(Boolean)
    if (parts.length) return parts[parts.length - 1]
  }
  return String(summary.sessionId || '会话').slice(0, 18)
}

/* -------------------------------------------------------------------- boot */

export function apply(ctx, config) {
  const cfg = config && typeof config === 'object' ? config : {}
  const state = loadState()
  const digest = tokenDigest(state.token)
  const hidden = loadHidden()
  const feeds = new Map()

  const isLoopback = (req) => {
    const address = String((req.socket && req.socket.remoteAddress) || '')
    return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1'
  }

  const totpEnabled = () => Boolean(state.totp && state.totp.secret)

  /** The Mac's own browser talks to 127.0.0.1 with a loopback Host. A request
   * proxied by `tailscale serve` also arrives from 127.0.0.1, but keeps the
   * tailnet Host — so Host, not the socket, decides "the Mac itself". */
  const isLoopbackRequest = (req) => {
    if (!isLoopback(req)) return false
    const host = String((req.headers && req.headers.host) || '')
    const hostname = host.replace(/:\d+$/, '').replace(/^\[|\]$/g, '')
    return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '::1'
  }

  /** A request is trusted when it carries a minted device token, or the master
   * token from the loopback interface (the Mac itself). The master token alone
   * never works remotely once TOTP is enrolled. */
  const authed = (req) => {
    const header = typeof req.headers['x-pocket-token'] === 'string' ? req.headers['x-pocket-token'] : ''
    const cookieValue = (() => {
      const cookies = String(req.headers.cookie || '')
      for (const part of cookies.split(';')) {
        const [key, ...rest] = part.trim().split('=')
        if (key === COOKIE && rest.length) return rest.join('=')
      }
      return ''
    })()

    if (header) {
      const found = deviceByToken(state, header)
      if (found) {
        found.device.lastSeen = Date.now()
        return true
      }
      if (safeEqual(tokenDigest(header), digest)) {
        if (!totpEnabled() || isLoopbackRequest(req)) return true
      }
    }
    // Legacy browser cookie: the raw digest, set by the one-time token exchange.
    if (cookieValue && safeEqual(cookieValue, digest) && (!totpEnabled() || isLoopbackRequest(req))) return true
    return false
  }

  const refreshContext = async (feed, sessionId) => {
    if (Date.now() - feed.contextAt < 4000) return
    feed.contextAt = Date.now()
    try {
      const projections = await ctx.sessionController.projections({ sessionId }, new AbortController().signal)
      const values = projections && projections.values ? projections.values : {}
      const pressure = values.contextPressure
      if (pressure) {
        const used = Number(pressure.projectedTokens ?? pressure.pressureTokens ?? 0)
        const window = Number(pressure.contextWindow ?? 0)
        feed.context = { used, window, ratio: window > 0 ? Math.min(1, used / window) : null }
      }
    } catch {
      /* projections are optional */
    }
  }

  const feedFor = (sessionId) => {
    let feed = feeds.get(sessionId)
    if (!feed) {
      feed = new Feed(ctx, sessionId)
      feeds.set(sessionId, feed)
    }
    feed.touch()
    feed.start()
    return feed
  }

  const sweep = setInterval(() => {
    const now = Date.now()
    for (const [id, feed] of feeds) {
      if (now - feed.lastUsed > FEED_IDLE_MS) {
        feed.stop()
        feeds.delete(id)
      }
    }
  }, 60 * 1000)
  if (typeof sweep.unref === 'function') sweep.unref()

  /* Model guard. The phone surface must never run a model the owner blocked.
     Three chokepoints: the catalog (hide it), the explicit selection call
     (reject it), and the prompt path (a session may have been switched from
     the desktop, where the block does not apply). */
  const blockedModels = new Set(
    (Array.isArray(cfg.blockedModels) ? cfg.blockedModels : ['deepseek-v4-pro'])
      .filter((entry) => typeof entry === 'string' && entry.trim())
      .map((entry) => entry.trim())
  )
  const isBlockedModel = (selection) => {
    if (!selection || blockedModels.size === 0) return false
    const model = typeof selection.model === 'string' ? selection.model : ''
    if (!model) return false
    const provider = typeof selection.provider === 'string' ? selection.provider : ''
    return blockedModels.has(model) || (provider !== '' && blockedModels.has(`${provider}/${model}`))
  }
  const currentSelection = async (sessionId) => {
    try {
      const projections = await ctx.sessionController.projections({ sessionId }, new AbortController().signal)
      const selection = projections && projections.values ? projections.values.modelSelection : null
      return selection ? selection.next || selection.lastUsed || null : null
    } catch {
      return null
    }
  }
  const blockedMessage = (selection) =>
    `Pocket 已禁用 ${selection && selection.model ? selection.model : '该模型'}：请先把模型切到别的再发送。`

  const handle = async (req, res) => {
    let url
    try {
      url = new URL(req.url || '/', 'http://pocket.local')
    } catch {
      sendJson(res, 400, { ok: false, error: 'bad url' })
      return
    }
    const pathname = url.pathname
    const method = req.method || 'GET'

    // Tiny access log: makes "the phone never reached us" distinguishable from
    // "it reached us and was rejected". Rotates at ~256 KB.
    if (pathname.startsWith(`${PREFIX}/api/`) || pathname === `${PREFIX}/`) {
      try {
        const file = path.join(homeDir(), 'pocket', 'hits.log')
        if (fs.existsSync(file) && fs.statSync(file).size > 256 * 1024) fs.writeFileSync(file, '')
        fs.appendFileSync(file, `${new Date().toISOString()} ${method} ${pathname} host=${req.headers.host || ''} ua=${String(req.headers['user-agent'] || '').slice(0, 40)}\n`)
      } catch {
        /* best effort */
      }
    }

    try {
      /* ---- pairing ---- */
      if (pathname === `${PREFIX}/` || pathname === PREFIX) {
        if (method !== 'GET') return sendJson(res, 405, { ok: false, error: 'method' })
        const token = url.searchParams.get('token')
        if (token && !totpEnabled() && safeEqual(tokenDigest(token), digest)) {
          res.writeHead(302, {
            'set-cookie': `${COOKIE}=${digest}; Path=${PREFIX}; HttpOnly; SameSite=Lax; Max-Age=31536000`,
            location: `${PREFIX}/`
          })
          res.end()
          return
        }
        if (!authed(req)) return sendFile(res, path.join(WEB_DIR, 'unlock.html'), 200)
        return sendFile(res, path.join(WEB_DIR, 'index.html'))
      }

      if (pathname.startsWith(`${PREFIX}/static/`)) {
        const rel = decodeURIComponent(pathname.slice(`${PREFIX}/static/`.length))
        const file = path.resolve(WEB_DIR, rel)
        if (!file.startsWith(path.resolve(WEB_DIR))) return sendJson(res, 403, { ok: false, error: 'forbidden' })
        return sendFile(res, file)
      }

      if (pathname === `${PREFIX}/manifest.webmanifest`) return sendFile(res, path.join(WEB_DIR, 'manifest.webmanifest'))
      if (pathname === `${PREFIX}/icon-180.png`) return sendFile(res, path.join(WEB_DIR, 'icon-180.png'))
      if (pathname === `${PREFIX}/icon-512.png`) return sendFile(res, path.join(WEB_DIR, 'icon-512.png'))
      if (pathname === `${PREFIX}/icon.svg`) return sendFile(res, path.join(WEB_DIR, 'icon.svg'))

      /* ---- api ---- */
      /* ---- enrollment (loopback only) ---- */
      if (pathname === `${PREFIX}/setup` && method === 'GET') {
        if (!isLoopback(req)) return sendJson(res, 403, { ok: false, error: 'only on the Mac itself' })
        if (!state.totp) {
          state.totp = { secret: base32Encode(crypto.randomBytes(20)), createdAt: Date.now() }
          saveState(state)
        }
        const secret = state.totp.secret
        const otpauth = `otpauth://totp/DeepSeek:${encodeURIComponent(os.hostname())}?secret=${secret}&issuer=DeepSeek&period=30&digits=6`
        const grouped = secret.match(/.{1,4}/g).join(' ')
        const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>两步验证</title>
<style>body{margin:0;background:#151517;color:#f9fafb;font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;display:grid;place-items:center;min-height:100vh}
.card{max-width:520px;padding:28px;border:1px solid rgba(255,255,255,.12);border-radius:18px;background:#1e1e20}
h1{font-size:19px;margin:0 0 6px}p{color:#adb2b8;margin:0 0 14px}
code{display:block;font-family:ui-monospace,Menlo,monospace;font-size:17px;letter-spacing:2px;background:#101012;border:1px solid rgba(255,255,255,.1);border-radius:10px;padding:12px 14px;word-break:break-all;color:#e8eaed}
.small{font-size:12px;color:#81858c;word-break:break-all}
</style></head><body><div class="card">
<h1>两步验证（TOTP）</h1>
<p>在 Authenticator 里「添加账户 → 手动输入」，把下面这串密钥贴进去（每 30 秒 6 位数字）。</p>
<code>${grouped}</code>
<p class="small">otpauth: ${otpauth}</p>
<p>添加完成后，在手机 App 的配对页填入<b>令牌 + 当前 6 位验证码</b>。之后每次重新配对都需要验证码；日常使用走设备令牌，不用重复输入。</p>
<p class="small">丢失 Authenticator：在 Mac 上删除 ~/.dsh/pocket/state.json 里的 "totp" 字段并重启 DSH 即可重新绑定。</p>
</div></body></html>`
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' })
        res.end(html)
        return
      }

      if (pathname === `${PREFIX}/api/pair-info` && method === 'GET') {
        return sendJson(res, 200, { ok: true, totp: totpEnabled() })
      }

      if (pathname === `${PREFIX}/api/pair` && method === 'POST') {
        const body = await readBody(req, 8192)
        const token = typeof body.token === 'string' ? body.token : ''
        const code = typeof body.code === 'string' ? body.code : ''
        if (!token || !safeEqual(tokenDigest(token), digest)) {
          return sendJson(res, 401, { ok: false, error: '配对令牌不正确' })
        }
        if (totpEnabled() && !verifyTotp(state.totp.secret, code)) {
          return sendJson(res, 401, { ok: false, error: '验证码不正确或已过期' })
        }
        const minted = mintDevice(state, body.label)
        saveState(state)
        return sendJson(res, 200, {
          ok: true,
          deviceId: minted.id,
          deviceToken: minted.token,
          totp: totpEnabled()
        })
      }

      if (pathname === `${PREFIX}/api/enroll` && method === 'POST') {
        const body = await readBody(req, 8192)
        const token = typeof body.token === 'string' ? body.token : ''
        const code = typeof body.code === 'string' ? body.code : ''
        const publicKey = typeof body.publicKey === 'string' ? body.publicKey : ''
        if (!token || !safeEqual(tokenDigest(token), digest)) {
          return sendJson(res, 401, { ok: false, error: '配对令牌不正确' })
        }
        if (totpEnabled() && !verifyTotp(state.totp.secret, code)) {
          return sendJson(res, 401, { ok: false, error: '验证码不正确或已过期' })
        }
        if (!publicKey) return sendJson(res, 400, { ok: false, error: 'missing publicKey' })
        try {
          crypto.createPublicKey({ key: Buffer.from(publicKey, 'base64'), format: 'der', type: 'spki' })
        } catch {
          return sendJson(res, 400, { ok: false, error: '公钥格式不正确' })
        }
        const minted = mintDevice(state, body.label, publicKey)
        saveState(state)
        return sendJson(res, 200, { ok: true, deviceId: minted.id, deviceToken: minted.token, keyed: true })
      }

      if (pathname === `${PREFIX}/api/challenge` && method === 'POST') {
        const body = await readBody(req, 4096)
        const deviceId = typeof body.deviceId === 'string' ? body.deviceId : ''
        const record = state.devices[deviceId]
        if (!record || !record.publicKey) return sendJson(res, 404, { ok: false, error: '这台设备没有注册密钥' })
        const nonce = crypto.randomBytes(32).toString('hex')
        record.nonce = nonce
        record.nonceAt = Date.now()
        saveState(state)
        return sendJson(res, 200, { ok: true, nonce })
      }

      if (pathname === `${PREFIX}/api/verify` && method === 'POST') {
        const body = await readBody(req, 4096)
        const deviceId = typeof body.deviceId === 'string' ? body.deviceId : ''
        const signature = typeof body.signature === 'string' ? body.signature : ''
        const record = state.devices[deviceId]
        if (!record || !record.publicKey) return sendJson(res, 404, { ok: false, error: '这台设备没有注册密钥' })
        if (!record.nonce || Date.now() - (record.nonceAt || 0) > 120_000) {
          return sendJson(res, 401, { ok: false, error: '挑战已过期，请重试' })
        }
        const nonce = record.nonce
        delete record.nonce
        delete record.nonceAt
        let valid = false
        try {
          const key = crypto.createPublicKey({ key: Buffer.from(record.publicKey, 'base64'), format: 'der', type: 'spki' })
          valid = crypto.verify('sha256', Buffer.from(nonce), { key, dsaEncoding: 'der' }, Buffer.from(signature, 'base64'))
        } catch {
          valid = false
        }
        saveState(state)
        if (!valid) return sendJson(res, 401, { ok: false, error: 'Face ID 校验失败' })
        record.lastSeen = Date.now()
        const minted = mintDevice(state, record.label)
        record.tokenHash = minted.tokenHash
        saveState(state)
        return sendJson(res, 200, { ok: true, deviceId, deviceToken: minted.token })
      }

      if (!pathname.startsWith(`${PREFIX}/api/`)) return sendJson(res, 404, { ok: false, error: 'not found' })
      if (!authed(req)) return sendJson(res, 401, { ok: false, error: 'unauthorized' })
      const api = pathname.slice(`${PREFIX}/api/`.length)

      if (api === 'ping') return sendJson(res, 200, { ok: true, version: VERSION })

      if (api === 'sessions' && method === 'GET') {
        const listed = await ctx.sessionController.list({}, new AbortController().signal)
        const items = (listed && Array.isArray(listed.items) ? listed.items : [])
          .filter((item) => item && typeof item.sessionId === 'string')
          .map((item) => ({
            id: item.sessionId,
            title: sessionTitle(item),
            cwd: typeof item.cwd === 'string' ? item.cwd : '',
            running: item.running === true,
            updatedAt: typeof item.updatedAt === 'number' ? item.updatedAt : 0,
            blank: item.blank === true
          }))
          .filter((item) => {
            if (hidden.has(item.id)) return false
            // A session whose log file disappeared cannot accept writes any more.
            // Very fresh sessions may not have flushed their log yet, so keep those.
            if (Date.now() - item.updatedAt < 60_000) return true
            return sessionLogExists(item.id)
          })
        return sendJson(res, 200, { ok: true, items })
      }

      if (api === 'session' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' })
        const summary = await ctx.sessionController.inspect(id, new AbortController().signal).catch(() => null)
        if (!summary) return sendJson(res, 404, { ok: false, error: 'session not found' })
        const hasHistory = Array.isArray(summary.events) && summary.events.length > 0
        if (hasHistory && !sessionLogExists(id)) {
          return sendJson(res, 410, { ok: false, code: 'gone', error: '这个会话的日志文件已丢失，请新建一个会话' })
        }
        const feed = feedFor(id)
        await refreshContext(feed, id)
        const view = feed.view()
        if (!view.session.title) {
          const listed = await ctx.sessionController.list({}, new AbortController().signal).catch(() => null)
          const items = listed && Array.isArray(listed.items) ? listed.items : []
          const row = items.find((item) => item && item.sessionId === id)
          if (row) {
            view.session.title = sessionTitle(row)
            if (row.running === true) view.running = true
            if (typeof row.updatedAt === 'number') view.updatedAt = row.updatedAt
          }
        }
        return sendJson(res, 200, view)
      }

      if (api === 'events' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        const after = Number(url.searchParams.get('after') || '-1')
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' })
        const feed = feedFor(id)
        await refreshContext(feed, id)
        return sendJson(res, 200, {
          ok: true,
          rev: feed.rev,
          running: feed.running,
          live: feed.live,
          title: feed.title,
          context: feed.context,
          items: feed.changedSince(after)
        })
      }

      if (api === 'older' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        const before = Number(url.searchParams.get('before') || '0')
        if (!id || !Number.isFinite(before)) return sendJson(res, 400, { ok: false, error: 'bad request' })
        const feed = feedFor(id)
        const page = await ctx.sessionController.page(
          {
            address: { kind: 'session', sessionId: id },
            throughSeq: Math.max(feed.cursor, 0),
            beforeSeq: Math.max(0, Math.floor(before)),
            maxMessages: 40
          },
          new AbortController().signal
        )
        const records = page && Array.isArray(page.records) ? page.records : []
        const before0 = new Set(feed.items.map((item) => item.id))
        for (const record of records) {
          if (record && record.type === 'event' && record.event) feed.ingest(record.event)
        }
        const added = feed.items.filter((item) => !before0.has(item.id))
        feed.hasMore = page ? page.hasMore === true : false
        feed.rev += 1
        return sendJson(res, 200, { ok: true, items: added, hasMore: feed.hasMore, rev: feed.rev })
      }

      if (api === 'send' && method === 'POST') {
        const body = await readBody(req, 24 * 1024 * 1024)
        const id = typeof body.id === 'string' ? body.id : ''
        const text = typeof body.text === 'string' ? body.text.trim() : ''
        const rawImages = Array.isArray(body.images) ? body.images : []
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' })
        const content = []
        if (text) content.push({ type: 'text', text })
        for (const image of rawImages.slice(0, 6)) {
          if (!image || typeof image !== 'object') continue
          const mediaType = String(image.mediaType || 'image/jpeg')
          if (!/^image\/(png|jpeg|webp|gif)$/.test(mediaType)) continue
          const data = typeof image.data === 'string' ? image.data.replace(/^data:[^;]+;base64,/, '') : ''
          if (!data) continue
          content.push({ type: 'image', mediaType, data, ...(typeof image.name === 'string' && image.name ? { name: image.name } : {}) })
        }
        if (content.length === 0) return sendJson(res, 400, { ok: false, error: '消息为空' })
        let selection = await currentSelection(id)
        if (!selection) {
          const catalog = await ctx.sessionController.modelCatalog().catch(() => null)
          selection = catalog && catalog.default ? catalog.default : null
        }
        if (isBlockedModel(selection)) {
          return sendJson(res, 409, {
            ok: false,
            error: blockedMessage(selection),
            blocked: { provider: selection.provider, model: selection.model }
          })
        }
        const requestId = `pocket-${crypto.randomUUID()}`
        await ctx.sessionController.prompt(
          {
            requestId,
            sessionId: id,
            mode: body.mode === 'steer' ? 'steer' : 'queue',
            content,
            clientTimeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
          },
          new AbortController().signal
        )
        feedFor(id)
        return sendJson(res, 200, { ok: true, requestId })
      }

      if (api === 'cancel' && method === 'POST') {
        const body = await readBody(req, 4096)
        const id = typeof body.id === 'string' ? body.id : ''
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' })
        ctx.sessionController.cancel({ sessionId: id })
        return sendJson(res, 200, { ok: true })
      }

      if (api === 'totp-off' && method === 'POST') {
        state.totp = null
        saveState(state)
        return sendJson(res, 200, { ok: true, totp: false })
      }

      if (api === 'delete-session' && method === 'POST') {
        const body = await readBody(req, 4096)
        const id = typeof body.id === 'string' ? body.id : ''
        if (!id) return sendJson(res, 400, { ok: false, error: 'missing id' })
        if (ctx.sessions.get(id) || ctx.agents.get(id)) {
          hidden.add(id)
          saveHidden(hidden)
          return sendJson(res, 200, { ok: true, removed: false, hidden: true })
        }
        const root = path.join(homeDir(), 'sessions')
        let removed = false
        try {
          for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
            if (!entry.isDirectory()) continue
            const dir = path.join(root, entry.name, id)
            if (fs.existsSync(dir)) {
              fs.rmSync(dir, { recursive: true, force: true })
              removed = true
            }
          }
        } catch (error) {
          return sendJson(res, 500, { ok: false, error: String((error && error.message) || error) })
        }
        const feed = feeds.get(id)
        if (feed) {
          feed.stop()
          feeds.delete(id)
        }
        return sendJson(res, 200, { ok: true, removed })
      }

      if (api === 'permissions' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        const permissions = ctx.get('permissionPresets')
        if (!permissions) return sendJson(res, 200, { ok: false, error: '这个 profile 没有权限预设' })
        const catalog = permissions.catalog()
        let current = null
        try {
          const session = ctx.sessions.get(id)
          if (session) current = permissions.current(session)
        } catch {
          /* cold session: no current value yet */
        }
        return sendJson(res, 200, { ok: true, current, ...catalog })
      }

      if (api === 'permission' && method === 'POST') {
        const body = await readBody(req, 4096)
        const id = typeof body.id === 'string' ? body.id : ''
        const preset = typeof body.preset === 'string' ? body.preset : ''
        if (!id || !preset) return sendJson(res, 400, { ok: false, error: 'missing id or preset' })
        const permissions = ctx.get('permissionPresets')
        const approval = ctx.get('approval')
        const agent = ctx.agents.get(id)
        if (!permissions || !approval) return sendJson(res, 409, { ok: false, error: '这个 profile 没有权限预设' })
        if (!agent) return sendJson(res, 409, { ok: false, error: '会话还没激活：先发一条消息，再改权限' })
        try {
          permissions.apply(agent.session, preset, (policy) => approval.setPolicy(agent, policy))
        } catch (error) {
          return sendJson(res, 400, { ok: false, error: String((error && error.message) || error) })
        }
        return sendJson(res, 200, { ok: true, current: permissions.current(agent.session) })
      }

      if (api === 'models' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        const catalog = await ctx.sessionController.modelCatalog()
        let current = catalog.default
        if (id) {
          try {
            const projections = await ctx.sessionController.projections({ sessionId: id }, new AbortController().signal)
            const selection = projections && projections.values ? projections.values.modelSelection : null
            const next = selection ? selection.next || selection.lastUsed : null
            if (next) current = next
          } catch {
            /* fall back to the deployment default */
          }
        }
        const groups = (Array.isArray(catalog.groups) ? catalog.groups : [])
          .map((group) => ({
            ...group,
            models: (Array.isArray(group.models) ? group.models : []).filter(
              (model) => !isBlockedModel({ provider: group.id, model: model.id })
            )
          }))
          .filter((group) => group.models.length > 0)
        return sendJson(res, 200, {
          ok: true,
          default: catalog.default,
          groups,
          failures: catalog.failures || [],
          current,
          blocked: [...blockedModels]
        })
      }

      if (api === 'model' && method === 'POST') {
        const body = await readBody(req, 8192)
        const id = typeof body.id === 'string' ? body.id : ''
        const provider = typeof body.provider === 'string' ? body.provider : ''
        const model = typeof body.model === 'string' ? body.model : ''
        if (!id || !provider || !model) return sendJson(res, 400, { ok: false, error: 'missing id/provider/model' })
        if (isBlockedModel({ provider, model })) {
          return sendJson(res, 403, { ok: false, error: `Pocket 已禁用 ${model}，请在桌面端使用。` })
        }
        const result = await ctx.sessionController.selectModel({
          sessionId: id,
          provider,
          model,
          ...(typeof body.reasoningEffort === 'string' && body.reasoningEffort ? { reasoningEffort: body.reasoningEffort } : {})
        })
        // The controller answers `{ selected: {...} }`; flatten it for the app.
        const selection = result && result.selected ? result.selected : result
        return sendJson(res, 200, { ok: true, selection })
      }

      if (api === 'image' && method === 'GET') {
        const id = url.searchParams.get('id') || ''
        const ref = url.searchParams.get('ref') || ''
        if (!id || !ref) return sendJson(res, 400, { ok: false, error: 'missing id or ref' })
        const stored = await ctx.sessionController.attachment({ sessionId: id, attachmentId: ref })
        const bytes = Buffer.from(String(stored.data || ''), 'base64')
        const mediaType = (stored.attachment && stored.attachment.mediaType) || 'image/jpeg'
        res.writeHead(200, {
          'content-type': mediaType,
          'content-length': bytes.length,
          'cache-control': 'private, max-age=3600'
        })
        res.end(bytes)
        return
      }

      if (api === 'whale' && method === 'GET') {
        const file = path.join(homeDir(), '.dshw-usage.json')
        let ledger = null
        try {
          ledger = JSON.parse(fs.readFileSync(file, 'utf8'))
        } catch {
          ledger = null
        }
        if (!ledger) return sendJson(res, 200, { ok: false, error: '找不到鲸鱼挂件的数据文件' })
        const parts = new Intl.DateTimeFormat('en-GB', {
          timeZone: 'Asia/Shanghai',
          hour: '2-digit',
          minute: '2-digit',
          hour12: false
        }).formatToParts(new Date())
        const hour = Number(parts.find((part) => part.type === 'hour')?.value || '0')
        const minute = Number(parts.find((part) => part.type === 'minute')?.value || '0')
        const minutes = hour * 60 + minute
        // DeepSeek 优惠时段：00:30 – 08:30（北京时间）
        const offPeak = minutes >= 30 && minutes < 510
        const events = Array.isArray(ledger.events) ? ledger.events.slice(-24) : []
        return sendJson(res, 200, {
          ok: true,
          date: ledger.date || '',
          balance: typeof ledger.lastBalance === 'number' ? ledger.lastBalance : null,
          today: typeof ledger.todayUsage === 'number' ? ledger.todayUsage : null,
          history: ledger.history && typeof ledger.history === 'object' ? ledger.history : {},
          events: events.map((event) => ({
            ts: Number(event.ts) || 0,
            model: String(event.model || ''),
            cost: Number(event.cost) || 0,
            tokens: Number(event.tokens) || 0
          })),
          offPeak,
          peakLabel: offPeak ? '谷时（5 折）' : '峰时',
          updatedAt: (() => {
            try {
              return fs.statSync(file).mtimeMs
            } catch {
              return 0
            }
          })()
        })
      }

      if (api === 'new' && method === 'POST') {
        const body = await readBody(req, 4096)
        let cwd = typeof body.cwd === 'string' && body.cwd ? body.cwd : ''
        if (!cwd) {
          const listed = await ctx.sessionController.list({}, new AbortController().signal).catch(() => null)
          const items = listed && Array.isArray(listed.items) ? listed.items : []
          const first = items.find((item) => item && typeof item.cwd === 'string' && item.cwd)
          cwd = first ? first.cwd : os.homedir()
        }
        const created = await ctx.sessionController.create({ cwd })
        return sendJson(res, 200, { ok: true, id: created.sessionId, cwd })
      }

      return sendJson(res, 404, { ok: false, error: 'not found' })
    } catch (error) {
      const status = typeof error === 'object' && error && typeof error.status === 'number' ? error.status : 500
      const message = String((error && error.message) || error)
      log(ctx, 'warn', `${method} ${pathname} failed: ${message}`)
      return sendJson(res, status, { ok: false, error: message })
    }
  }

  let dispose
  try {
    dispose = ctx.webServer.register({ kind: 'prefix', path: PREFIX, handler: handle })
  } catch (error) {
    log(ctx, 'error', `route registration failed: ${String((error && error.message) || error)}`)
    return
  }

  ctx.effect(() => () => {
    clearInterval(sweep)
    for (const feed of feeds.values()) feed.stop()
    feeds.clear()
    try {
      dispose()
    } catch {
      /* ignore */
    }
  })

  const announce = () => {
    try {
      const origin = ctx.webServer.getOrigin()
      log(ctx, 'info', `ready — open ${origin}${PREFIX}/?token=${state.token}`)
    } catch {
      /* port not bound yet */
    }
  }
  const timer = setTimeout(announce, 1500)
  if (typeof timer.unref === 'function') timer.unref()

  log(ctx, 'info', `mounted at ${PREFIX} (v${VERSION})`)
}

export default { name, inject, apply }
