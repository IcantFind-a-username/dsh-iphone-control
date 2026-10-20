/* dsh-pocket — the phone side. No framework, no build step. */

const $ = (sel) => document.querySelector(sel);
const api = (path) => `./api/${path}`;

const state = {
  sessionId: null,
  sessions: [],
  items: new Map(),
  order: [],
  rev: -1,
  running: false,
  live: { text: '', think: '' },
  oldestSeq: null,
  hasMore: false,
  title: 'Pocket',
  cwd: '',
  online: false,
  lastError: '',
  pending: null,
  atBottom: true,
  loadingOlder: false
};

const openTools = new Set();
const IMAGE_TYPES = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/* ------------------------------------------------------------------ utils */

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function relativeTime(time) {
  if (!time) return '';
  const diff = Date.now() - time;
  if (diff < 60_000) return '刚刚';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)} 分钟前`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)} 小时前`;
  if (diff < 7 * 86_400_000) return `${Math.floor(diff / 86_400_000)} 天前`;
  const date = new Date(time);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

function toast(message, ms = 2200) {
  const node = $('#toast');
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => {
    node.hidden = true;
  }, ms);
}

/* -------------------------------------------------------------- markdown */

function renderMarkdown(source) {
  const text = String(source || '');
  const codeBlocks = [];
  let work = text.replace(/```([\w+-]*)\n?([\s\S]*?)```/g, (_match, lang, code) => {
    const index = codeBlocks.push({ lang: String(lang || '').trim(), code }) - 1;
    return `\u0000CODE${index}\u0000`;
  });

  work = escapeHtml(work);

  const lines = work.split('\n');
  const out = [];
  let paragraph = [];
  let list = null;

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join('\n'))}</p>`);
      paragraph = [];
    }
  };
  const flushList = () => {
    if (list) {
      out.push(`<${list.tag}>${list.items.map((item) => `<li>${inline(item)}</li>`).join('')}</${list.tag}>`);
      list = null;
    }
  };

  for (const rawLine of lines) {
    const line = rawLine.replace(/\s+$/, '');
    if (!line.trim()) {
      flushParagraph();
      flushList();
      continue;
    }
    const fence = line.match(/^\u0000CODE(\d+)\u0000$/);
    if (fence) {
      flushParagraph();
      flushList();
      const block = codeBlocks[Number(fence[1])];
      const label = block && block.lang ? `<div class="code-lang">${escapeHtml(block.lang)}</div>` : '';
      out.push(`<pre>${label}<code>${escapeHtml(block ? block.code.replace(/\n$/, '') : '')}</code></pre>`);
      continue;
    }
    const heading = line.match(/^(#{1,3})\s+(.*)$/);
    if (heading) {
      flushParagraph();
      flushList();
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      continue;
    }
    if (/^(-{3,}|\*{3,})$/.test(line.trim())) {
      flushParagraph();
      flushList();
      out.push('<hr>');
      continue;
    }
    if (/^&gt;\s?/.test(line)) {
      flushParagraph();
      flushList();
      out.push(`<blockquote>${inline(line.replace(/^&gt;\s?/, ''))}</blockquote>`);
      continue;
    }
    const bullet = line.match(/^\s*[-*+]\s+(.*)$/);
    const ordered = line.match(/^\s*\d+[.)]\s+(.*)$/);
    if (bullet || ordered) {
      flushParagraph();
      const tag = ordered ? 'ol' : 'ul';
      if (!list || list.tag !== tag) {
        flushList();
        list = { tag, items: [] };
      }
      list.items.push((bullet || ordered)[1]);
      continue;
    }
    if (list) {
      flushList();
    }
    paragraph.push(line);
  }
  flushParagraph();
  flushList();
  return out.join('');
}

function inline(value) {
  let out = value;
  out = out.replace(/`([^`]+)`/g, '<code class="inline">$1</code>');
  out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  out = out.replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)/g, '$1<em>$2</em>');
  out = out.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer noopener">$1</a>');
  out = out.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, '$1<a href="$2" target="_blank" rel="noreferrer noopener">$2</a>');
  return out.replace(/\n/g, '<br>');
}

/* ----------------------------------------------------------------- fetch */

async function getJson(path, options) {
  const response = await fetch(api(path), {
    credentials: 'same-origin',
    headers: { accept: 'application/json' },
    ...options
  });
  if (response.status === 401) {
    location.reload();
    throw new Error('unauthorized');
  }
  const value = await response.json().catch(() => ({ ok: false, error: `HTTP ${response.status}` }));
  if (!response.ok || value.ok === false) {
    throw new Error(value.error || `HTTP ${response.status}`);
  }
  return value;
}

/* ------------------------------------------------------------- rendering */

function sortedItems() {
  return state.order.map((id) => state.items.get(id)).filter(Boolean);
}

function render() {
  const log = $('#log');
  const scroll = $('#scroller');
  const nearBottom = state.atBottom;
  const previousHeight = scroll.scrollHeight;

  log.textContent = '';
  const items = sortedItems();

  if (!items.length && !state.running && !state.live.text && !state.live.think && !state.pending) {
    const empty = el('div', 'empty');
    empty.appendChild(el('div', 'orb'));
    empty.appendChild(el('h2', '', '开始对话'));
    empty.appendChild(el('p', '', '在手机上继续你的 Harness 会话'));
    log.appendChild(empty);
  }

  if (state.hasMore && items.length) {
    const more = el('button', 'text-btn', state.loadingOlder ? '正在加载…' : '加载更早的消息');
    more.style.alignSelf = 'center';
    more.style.opacity = '0.8';
    more.onclick = loadOlder;
    log.appendChild(more);
  }

  for (const item of items) {
    log.appendChild(renderItem(item));
  }

  if (state.pending) {
    const msg = el('div', 'msg user');
    const bubble = el('div', 'bubble', state.pending.text || '（图片）');
    bubble.style.opacity = '0.72';
    msg.appendChild(bubble);
    log.appendChild(msg);
  }

  const live = buildLive();
  if (live) log.appendChild(live);

  if (nearBottom) {
    requestAnimationFrame(() => {
      scroll.scrollTop = scroll.scrollHeight;
    });
  } else {
    scroll.scrollTop = scroll.scrollHeight - previousHeight + scroll.scrollTop;
  }
  updateJump();
}

function renderItem(item) {
  if (item.k === 'u') {
    const msg = el('div', 'msg user');
    const bubble = el('div', 'bubble');
    if (item.imgs && item.imgs.length) {
      const images = el('div', 'imgs');
      for (const image of item.imgs) images.appendChild(el('span', '', '照片'));
      bubble.appendChild(images);
    }
    if (item.text) bubble.appendChild(document.createTextNode(item.text));
    msg.appendChild(bubble);
    return msg;
  }

  if (item.k === 'a') {
    const msg = el('div', 'msg ai');
    if (item.think) msg.appendChild(renderThink(item.think, false, !item.text));
    const body = el('div', 'ai-text');
    body.innerHTML = renderMarkdown(item.text || '');
    if (item.usage) body.appendChild(renderStats(item.usage));
    msg.appendChild(body);
    return msg;
  }

  if (item.k === 'n') {
    return el('div', 'notice', item.text || '');
  }

  if (item.k === 't') {
    const tool = el('div', `tool ${item.status || ''}`.trim());
    if (openTools.has(item.callId)) tool.classList.add('open');
    const head = el('div', 'tool-head');
    head.appendChild(el('span', 'tool-dot'));
    head.appendChild(el('span', 'tool-name', item.label || item.name || '工具'));
    if (item.detail) head.appendChild(el('span', 'tool-detail', item.detail));
    head.onclick = () => {
      if (openTools.has(item.callId)) openTools.delete(item.callId);
      else openTools.add(item.callId);
      tool.classList.toggle('open');
    };
    tool.appendChild(head);
    const body = el('div', 'tool-body', item.result || '运行中…');
    tool.appendChild(body);
    return tool;
  }

  return el('div', 'notice', item.text || '');
}

function renderStats(usage) {
  const line = el('div', 'stats');
  if (usage.output) line.appendChild(el('span', '', `${formatNumber(usage.output)} tok`));
  if (usage.tps) line.appendChild(el('span', '', `${usage.tps} tok/s`));
  if (usage.cacheRate !== null && usage.cacheRate !== undefined) line.appendChild(el('span', '', `缓存 ${usage.cacheRate}%`));
  if (usage.secs) line.appendChild(el('span', '', `${usage.secs}s`));
  return line;
}

function formatNumber(value) {
  return Number(value || 0).toLocaleString('en-US');
}

function renderThink(text, streaming, expanded) {
  const wrap = el('div', expanded ? 'think' : 'think collapsed');
  const head = el('div', 'think-head');
  if (streaming) head.appendChild(el('div', 'shimmer'));
  head.appendChild(el('span', '', streaming ? '思考中' : '思考过程'));
  wrap.appendChild(head);
  const body = el('div', 'think-body', text);
  wrap.appendChild(body);
  wrap.onclick = () => wrap.classList.toggle('collapsed');
  return wrap;
}

function buildLive() {
  const hasLive = state.live.text || state.live.think;
  if (!state.running && !hasLive) return null;
  const msg = el('div', 'msg ai live');
  if (state.live.think) msg.appendChild(renderThink(state.live.think, true));
  const body = el('div', 'ai-text');
  body.innerHTML = renderMarkdown(state.live.text || '');
  if (!state.live.text) {
    const line = el('div', 'think-head');
    line.appendChild(el('div', 'shimmer'));
    body.appendChild(line);
  } else {
    body.appendChild(el('span', 'caret'));
  }
  msg.appendChild(body);
  return msg;
}

function updateLive() {
  const log = $('#log');
  const previous = log.querySelector('.msg.live');
  if (!state.running && !state.live.text && !state.live.think) {
    if (previous) previous.remove();
    return;
  }
  if (!previous) {
    render();
    if (state.atBottom) scrollToBottom();
    return;
  }
  if (!state.live.text) {
    const body = previous.querySelector('.ai-text');
    if (body) body.innerHTML = '';
    if (body && !body.querySelector('.think-head')) {
      const line = el('div', 'think-head');
      line.appendChild(el('div', 'shimmer'));
      body.appendChild(line);
    }
    if (state.live.think) {
      const think = previous.querySelector('.think');
      if (think) think.querySelector('.think-body').textContent = state.live.think;
    }
    return;
  }
  const body = previous.querySelector('.ai-text');
  if (body) {
    body.innerHTML = renderMarkdown(state.live.text);
    body.appendChild(el('span', 'caret'));
  }
  if (state.live.think) {
    const think = previous.querySelector('.think');
    if (think) think.querySelector('.think-body').textContent = state.live.think;
  }
  if (state.atBottom) scrollToBottom();
}

/* -------------------------------------------------------------- sessions */

async function loadSessions() {
  const value = await getJson('sessions');
  state.sessions = value.items || [];
  return state.sessions;
}

function renderSessionList() {
  const list = $('#sessionList');
  list.textContent = '';
  for (const session of state.sessions) {
    const row = el('div', `row${session.id === state.sessionId ? ' active' : ''}`);
    const meta = el('div', 'meta');
    meta.appendChild(el('div', 'name', session.title || '会话'));
    const when = session.running ? '正在回复…' : relativeTime(session.updatedAt);
    meta.appendChild(el('div', 'when', when));
    row.appendChild(meta);
    if (session.running) row.appendChild(el('div', 'live'));
    row.onclick = () => {
      closeSheet();
      if (session.id !== state.sessionId) openSession(session.id);
    };
    list.appendChild(row);
  }
  if (!state.sessions.length) {
    list.appendChild(el('div', 'row', '还没有会话，点右上角新建一个'));
  }
}

function openSheet() {
  loadSessions().then(renderSessionList).catch((error) => toast(error.message));
  $('#sheet').hidden = false;
}

function closeSheet() {
  $('#sheet').hidden = true;
}

/* --------------------------------------------------------------- session */

async function openSession(id) {
  state.sessionId = id;
  localStorage.setItem('pocket.session', id);
  state.items = new Map();
  state.order = [];
  state.rev = -1;
  state.running = false;
  state.live = { text: '', think: '' };
  state.pending = null;
  state.hasMore = false;
  state.oldestSeq = null;
  state.title = '会话';
  setStatus('connecting');
  render();

  const value = await getJson(`session?id=${encodeURIComponent(id)}`);
  state.title = (value.session && value.session.title) || state.title;
  applyItems(value.items || []);
  state.rev = value.rev ?? -1;
  state.running = value.running === true;
  state.live = value.live || { text: '', think: '' };
  state.hasMore = value.hasMore === true;
  state.oldestSeq = value.oldestSeq ?? null;
  const known = state.sessions.find((session) => session.id === id);
  if (known && known.title) state.title = known.title;
  if (known) state.cwd = known.cwd || '';
  updateHeader();
  render();
  setStatus('online');
  schedulePoll(300);
}

function applyItems(items) {
  let added = 0;
  let updated = 0;
  for (const item of items) {
    if (!item || !item.id) continue;
    if (state.items.has(item.id)) {
      Object.assign(state.items.get(item.id), item);
      updated += 1;
    } else {
      state.items.set(item.id, item);
      state.order.push(item.id);
      added += 1;
    }
    if (state.pending && item.k === 'u' && item.text === state.pending.text) {
      state.pending = null;
    }
  }
  if (added) {
    state.order.sort((left, right) => (state.items.get(left).seq ?? 0) - (state.items.get(right).seq ?? 0));
  }
  return { added, updated };
}

let pollTimer = null;
function schedulePoll(delay) {
  clearTimeout(pollTimer);
  pollTimer = setTimeout(poll, delay);
}

async function poll() {
  if (!state.sessionId) return;
  try {
    const value = await getJson(`events?id=${encodeURIComponent(state.sessionId)}&after=${state.rev}`);
    const change = applyItems(value.items || []);
    state.rev = value.rev ?? state.rev;
    state.running = value.running === true;
    state.live = value.live || { text: '', think: '' };
    if (value.title) state.title = value.title;
    if (change.added) {
      render();
      if (state.atBottom) scrollToBottom();
    } else {
      updateLive();
    }
    updateHeader();
    setStatus('online');
    schedulePoll(state.running ? 450 : 1200);
  } catch (error) {
    setStatus('offline', error.message);
    schedulePoll(2500);
  }
}

async function loadOlder() {
  if (state.loadingOlder || !state.sessionId) return;
  const first = sortedItems()[0];
  if (!first || typeof first.seq !== 'number') return;
  state.loadingOlder = true;
  render();
  try {
    const value = await getJson(`older?id=${encodeURIComponent(state.sessionId)}&before=${Math.floor(first.seq)}`);
    applyItems(value.items || []);
    state.hasMore = value.hasMore === true;
    state.rev = Math.max(state.rev, value.rev ?? state.rev);
  } catch (error) {
    toast(error.message);
  } finally {
    state.loadingOlder = false;
    render();
  }
}

/* ------------------------------------------------------------------ send */

async function send() {
  const input = $('#input');
  const text = input.value.trim();
  if ((!text && !attachments.length) || !state.sessionId) return;
  const payload = {
    id: state.sessionId,
    text,
    images: attachments.map((item) => ({ mediaType: item.mediaType, data: item.data, name: item.name }))
  };
  state.pending = { text };
  input.value = '';
  autoGrow();
  clearAttachments();
  updateSendState();
  render();
  scrollToBottom();
  try {
    await getJson('send', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    });
    state.pending = null;
    schedulePoll(250);
  } catch (error) {
    state.pending = null;
    toast(error.message, 3200);
    render();
  }
}

async function stopRun() {
  if (!state.sessionId) return;
  try {
    await getJson('cancel', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ id: state.sessionId })
    });
    toast('已请求停止');
  } catch (error) {
    toast(error.message);
  }
}

async function newSession() {
  try {
    const value = await getJson('new', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ cwd: state.cwd || undefined })
    });
    await loadSessions();
    await openSession(value.id);
    toast('已新建会话');
  } catch (error) {
    toast(error.message);
  }
}

/* ------------------------------------------------------------- attachments */

const attachments = [];

function readFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(new Error('读取图片失败'));
    reader.readAsDataURL(file);
  });
}

async function compress(file) {
  const url = URL.createObjectURL(file);
  try {
    const image = await new Promise((resolve, reject) => {
      const node = new Image();
      node.onload = () => resolve(node);
      node.onerror = () => reject(new Error('无法解析图片'));
      node.src = url;
    });
    const max = 1600;
    const scale = Math.min(1, max / Math.max(image.width, image.height));
    if (scale === 1 && file.size < 900_000) {
      const data = await readFile(file);
      return { data: data.replace(/^data:[^;]+;base64,/, ''), mediaType: file.type || 'image/jpeg', name: file.name || 'photo.jpg' };
    }
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(image.width * scale);
    canvas.height = Math.round(image.height * scale);
    const context = canvas.getContext('2d');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const dataUrl = canvas.toDataURL('image/jpeg', 0.86);
    return { data: dataUrl.replace(/^data:[^;]+;base64,/, ''), mediaType: 'image/jpeg', name: 'photo.jpg' };
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function addFiles(files) {
  for (const file of Array.from(files).slice(0, 6 - attachments.length)) {
    if (!file.type.startsWith('image/')) continue;
    if (file.size > 12 * 1024 * 1024) {
      toast('图片太大了');
      continue;
    }
    try {
      const value = await compress(file);
      attachments.push({ ...value, preview: `data:${value.mediaType};base64,${value.data}` });
    } catch (error) {
      toast(error.message);
    }
  }
  renderPreviews();
  updateSendState();
}

function renderPreviews() {
  const box = $('#previews');
  box.textContent = '';
  box.hidden = attachments.length === 0;
  attachments.forEach((item, index) => {
    const thumb = el('div', 'thumb');
    const image = document.createElement('img');
    image.src = item.preview;
    thumb.appendChild(image);
    const remove = el('button', '', '×');
    remove.onclick = () => {
      attachments.splice(index, 1);
      renderPreviews();
      updateSendState();
    };
    thumb.appendChild(remove);
    box.appendChild(thumb);
  });
}

function clearAttachments() {
  attachments.length = 0;
  renderPreviews();
}

/* --------------------------------------------------------------- chrome */

function setStatus(mode, detail) {
  const dot = $('#dot');
  const text = $('#subText');
  dot.className = 'dot';
  if (mode === 'online') {
    state.online = true;
    if (state.running) {
      dot.classList.add('busy');
      text.textContent = '正在回复…';
    } else {
      dot.classList.add('on');
      text.textContent = state.cwd ? shortPath(state.cwd) : '已连接';
    }
  } else if (mode === 'connecting') {
    text.textContent = '正在连接…';
  } else {
    state.online = false;
    dot.classList.add('err');
    text.textContent = '连接中断，重试中…';
    if (detail) state.lastError = detail;
  }
}

function shortPath(value) {
  const parts = String(value).split('/').filter(Boolean);
  return parts.length ? parts[parts.length - 1] : value;
}

function updateHeader() {
  $('#title').textContent = state.title || 'Pocket';
  $('#btnStop').hidden = !state.running;
  $('#btnSend').hidden = state.running;
  if (state.online) setStatus('online');
}

function scrollToBottom() {
  const scroller = $('#scroller');
  state.atBottom = true;
  scroller.scrollTop = scroller.scrollHeight;
  updateJump();
}

function updateJump() {
  $('#jump').hidden = state.atBottom;
}

function autoGrow() {
  const input = $('#input');
  input.style.height = 'auto';
  input.style.height = `${Math.min(input.scrollHeight, 118)}px`;
}

function updateSendState() {
  const text = $('#input').value.trim();
  $('#btnSend').disabled = !text && attachments.length === 0;
}

/* ----------------------------------------------------------------- boot */

function bind() {
  $('#btnSessions').onclick = openSheet;
  $('#btnNew').onclick = newSession;
  $('#btnNewSheet').onclick = () => {
    closeSheet();
    newSession();
  };
  $('#sheet').addEventListener('click', (event) => {
    if (event.target.hasAttribute('data-close')) closeSheet();
  });
  $('#btnAttach').onclick = () => $('#file').click();
  $('#file').onchange = (event) => {
    addFiles(event.target.files);
    event.target.value = '';
  };
  $('#btnSend').onclick = send;
  $('#btnStop').onclick = stopRun;
  $('#jump').onclick = scrollToBottom;

  const input = $('#input');
  input.addEventListener('input', () => {
    autoGrow();
    updateSendState();
  });
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      send();
    }
  });
  input.addEventListener('focus', () => setTimeout(scrollToBottom, 250));

  const scroller = $('#scroller');
  scroller.addEventListener('scroll', () => {
    const distance = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight;
    state.atBottom = distance < 120;
    updateJump();
    if (
      state.hasMore &&
      !state.loadingOlder &&
      scroller.scrollHeight > scroller.clientHeight + 200 &&
      scroller.scrollTop < 40
    ) {
      loadOlder();
    }
  }, { passive: true });

  if (window.visualViewport) {
    const fix = () => {
      document.documentElement.style.setProperty('--vh', `${window.visualViewport.height}px`);
    };
    window.visualViewport.addEventListener('resize', fix);
    fix();
  }
}

async function boot() {
  bind();
  setStatus('connecting');
  try {
    const sessions = await loadSessions();
    const fromQuery = new URLSearchParams(location.search).get('session');
    const remembered = localStorage.getItem('pocket.session');
    const target = fromQuery
      ? fromQuery
      : ((remembered && sessions.find((session) => session.id === remembered && !session.blank)) ||
        sessions.find((session) => !session.blank) ||
        sessions[0] || { id: null }).id;
    if (target) {
      await openSession(target);
    } else {
      await newSession();
    }
  } catch (error) {
    setStatus('offline', error.message);
    schedulePoll(2000);
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    schedulePoll(60);
  }
});

boot();
