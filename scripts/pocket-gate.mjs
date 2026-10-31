#!/usr/bin/env node
/**
 * Pocket gate — a tiny reverse proxy that exposes ONLY /pocket/* from the DSH
 * web server, so a public Funnel/Cloudflare entry can never reach `/`, `/api`,
 * or any other plugin route.
 *
 *   node scripts/pocket-gate.mjs            # 127.0.0.1:64045 -> 127.0.0.1:64044
 *
 * It rewrites Host to FACADE_HOST so the plugin keeps treating the request as
 * remote (TOTP stays enforced instead of the loopback exemption).
 */
import http from 'node:http'

const PORT = Number(process.env.POCKET_GATE_PORT || 64045)
const TARGET_PORT = Number(process.env.POCKET_TARGET_PORT || 64044)
const FACADE_HOST = process.env.POCKET_FACADE_HOST || 'yiqun-mac.tail8e99e6.ts.net'
const PREFIX = '/pocket'

const server = http.createServer((req, res) => {
  const url = req.url || '/'
  const path = url.split('?')[0]
  if (!(path === PREFIX || path.startsWith(`${PREFIX}/`))) {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
    res.end('not found')
    return
  }

  const headers = { ...req.headers, host: FACADE_HOST }
  headers['x-forwarded-for'] = req.socket.remoteAddress || ''

  const upstream = http.request(
    { host: '127.0.0.1', port: TARGET_PORT, method: req.method, path: url, headers },
    (answer) => {
      res.writeHead(answer.statusCode || 502, answer.headers)
      answer.pipe(res)
    }
  )
  upstream.on('error', () => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    }
    res.end('upstream unavailable')
  })
  req.pipe(upstream)
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`pocket gate listening on http://127.0.0.1:${PORT} -> 127.0.0.1:${TARGET_PORT} (only ${PREFIX}/*)`)
})
