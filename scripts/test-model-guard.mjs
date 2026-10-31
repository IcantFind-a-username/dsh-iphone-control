// Regression test for the Pocket model guard (blockedModels).
//
//   node scripts/test-model-guard.mjs
//
// Boots the host plugin against a fake DSH context and drives the three
// chokepoints: the model catalog, the explicit selection call, and the prompt
// path. Needs a readable ~/.dsh/pocket/state.json (created on first run).
import { EventEmitter } from 'node:events'
import { readFileSync } from 'node:fs'
import os from 'node:os'

const token = JSON.parse(readFileSync(`${os.homedir()}/.dsh/pocket/state.json`, 'utf8')).token
const plugin = await import(new URL('../index.js', import.meta.url))
const PLUGIN = '../index.js'

const groups = () => [
  {
    id: 'deepseek-account',
    name: 'DeepSeek Account',
    models: [
      { id: 'deepseek-flash', name: 'DeepSeek-V4.1-Flash' },
      { id: 'deepseek-v4-pro', name: 'DeepSeek-V4-Pro' }
    ]
  }
]

function boot (config, selection) {
  const state = { handler: null, selection, prompts: 0 }
  const ctx = {
    webServer: {
      register: (route) => {
        state.handler = route.handler
        return () => {}
      },
      getOrigin: () => 'http://127.0.0.1:0'
    },
    sessionController: {
      modelCatalog: async () => ({
        default: { provider: 'deepseek-account', model: 'deepseek-flash', reasoningEffort: 'high' },
        groups: groups()
      }),
      projections: async () => ({ values: { modelSelection: state.selection ? { next: state.selection } : null } }),
      selectModel: async () => ({ selected: state.selection }),
      prompt: async () => {
        state.prompts += 1
        return { ok: true }
      },
      list: async () => ({ items: [] })
    },
    sessions: { get: () => null },
    agents: { get: () => null },
    get: () => undefined,
    effect: (fn) => {
      fn()
    }
  }
  plugin.apply(ctx, config)
  return state
}

async function call (state, method, url, body) {
  const req = new EventEmitter()
  req.method = method
  req.url = url
  req.headers = { 'x-pocket-token': token }
  req.destroy = () => {}
  const out = { status: 0, body: '' }
  const res = {
    writeHead (status) {
      out.status = status
    },
    end (chunk) {
      out.body = chunk ? String(chunk) : ''
      out.done?.()
    },
    setHeader () {},
    getHeader () {
      return undefined
    },
    write () {}
  }
  const done = new Promise((resolve) => {
    out.done = resolve
  })
  state.handler(req, res)
  setImmediate(() => {
    if (body !== undefined) req.emit('data', Buffer.from(JSON.stringify(body)))
    req.emit('end')
  })
  await done
  return { status: out.status, json: out.body ? JSON.parse(out.body) : null }
}

const results = []
const check = (name, ok, detail) => {
  results.push({ name, ok })
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `  ${JSON.stringify(detail)}`}`)
}

// Default config, session sitting on v4-pro.
{
  const state = boot({}, { provider: 'deepseek-account', model: 'deepseek-v4-pro' })
  const models = await call(state, 'GET', '/pocket/api/models?id=s1')
  const ids = (models.json?.groups || []).flatMap((group) => group.models.map((model) => model.id))
  check('catalog hides v4-pro', models.status === 200 && !ids.includes('deepseek-v4-pro') && ids.includes('deepseek-flash'), ids)
  check('catalog reports blocked list', JSON.stringify(models.json?.blocked) === '["deepseek-v4-pro"]', models.json?.blocked)
  check('catalog still reports the real current model', models.json?.current?.model === 'deepseek-v4-pro', models.json?.current)

  const pick = await call(state, 'POST', '/pocket/api/model', { id: 's1', provider: 'deepseek-account', model: 'deepseek-v4-pro' })
  check('selecting v4-pro is rejected', pick.status === 403 && pick.json?.ok === false, [pick.status, pick.json])

  const send = await call(state, 'POST', '/pocket/api/send', { id: 's1', text: 'hi' })
  check('prompt on v4-pro is blocked', send.status === 409 && send.json?.ok === false && state.prompts === 0, [send.status, send.json])
}

// Session on flash: normal traffic passes.
{
  const state = boot({}, { provider: 'deepseek-account', model: 'deepseek-flash' })
  const send = await call(state, 'POST', '/pocket/api/send', { id: 's1', text: 'hi' })
  check('prompt on flash goes through', send.status === 200 && send.json?.ok === true && state.prompts === 1, [send.status, send.json])
}

// No per-session selection yet: the deployment default decides (flash here).
{
  const state = boot({}, null)
  const models = await call(state, 'GET', '/pocket/api/models?id=s1')
  check('no selection falls back to default for display', models.json?.current?.model === 'deepseek-flash', models.json?.current)
  const send = await call(state, 'POST', '/pocket/api/send', { id: 's1', text: 'hi' })
  check('no selection falls back to default for prompt', send.status === 200 && state.prompts === 1, [send.status, send.json])
}

// Provider-qualified deny entry.
{
  const state = boot({ blockedModels: ['deepseek-account/deepseek-v4-pro'] }, { provider: 'deepseek-account', model: 'deepseek-v4-pro' })
  const send = await call(state, 'POST', '/pocket/api/send', { id: 's1', text: 'hi' })
  check('provider/model entry also blocks', send.status === 409, [send.status, send.json])
}

// Explicitly empty denylist turns the guard off.
{
  const state = boot({ blockedModels: [] }, { provider: 'deepseek-account', model: 'deepseek-v4-pro' })
  const models = await call(state, 'GET', '/pocket/api/models?id=s1')
  const ids = (models.json?.groups || []).flatMap((group) => group.models.map((model) => model.id))
  check('empty denylist shows v4-pro again', ids.includes('deepseek-v4-pro'), ids)
  const send = await call(state, 'POST', '/pocket/api/send', { id: 's1', text: 'hi' })
  check('empty denylist lets v4-pro through', send.status === 200, [send.status, send.json])
}

const failed = results.filter((result) => !result.ok)
console.log(`\n${results.length - failed.length}/${results.length} passed (${PLUGIN})`)
process.exit(failed.length ? 1 : 0)
