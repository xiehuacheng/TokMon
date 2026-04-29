/* AgentMon SPA */
let currentTab = 'tokmon';
let sessionsPage = 1;
let sessionsPageSize = 15;
let sessionsFilters = { source: '', project: '', model: '', q: '', archived: '0' };
let sessionsManageMode = false;
let selectedSessionIds = new Set();
let showLastPrompt = true;
let skillsManageMode = false;
let selectedSkillNames = new Set();
let skillsSearch = '';
let mcpManageMode = false;
let selectedMcpNames = new Set();
let mcpSearch = '';
let tokmonInstance = null;

const $ = (sel) => document.querySelector(sel);
const $content = () => $('#content');
const $headerActions = () => $('#headerActions');

/* ── Nav ── */
$('#navTabs').addEventListener('click', (e) => {
  const btn = e.target.closest('.tbtn');
  if (!btn) return;
  document.querySelectorAll('#navTabs .tbtn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  currentTab = btn.dataset.tab;
  sessionsPage = 1;
  render();
});

function render() {
  if (currentTab !== 'tokmon') {
    destroyTokMon();
    clearHeaderActions();
  }
  const views = { tokmon: renderTokMon, sessions: renderSessions, skills: renderSkills, mcp: renderMcp, settings: renderSettings };
  (views[currentTab] || views.tokmon)();
}

/* ── Helpers ── */
function esc(s) { if (!s) return ''; const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
function trunc(s, n) { return s && s.length > n ? s.slice(0, n) + '...' : s || ''; }
function relTime(iso) {
  if (!iso) return '';
  const d = new Date(iso), now = Date.now(), diff = now - d.getTime();
  if (diff < 60000) return 'just now';
  if (diff < 3600000) return Math.floor(diff / 60000) + 'm ago';
  if (diff < 86400000) return Math.floor(diff / 3600000) + 'h ago';
  return d.toLocaleDateString('zh-CN');
}
function sourceBadge(s) { return s === 'claude-code' ? '<span class="badge badge-claude">CC</span>' : '<span class="badge badge-codex">Codex</span>'; }

async function api(path, opts) {
  const res = await fetch('/api' + path, opts);
  return res.json();
}

function openModal(html) {
  $('#modal').innerHTML = html;
  $('#modalOverlay').classList.add('open');
}
function closeModal() { $('#modalOverlay').classList.remove('open'); }
$('#modalOverlay').addEventListener('click', (e) => { if (e.target === $('#modalOverlay')) closeModal(); });

/* ── TokMon View ── */
function renderTokMon() {
  if (tokmonInstance) return;
  renderTokensHeaderActions();
  $content().innerHTML = `
    <div class="tokmon-view" id="tokmonView">
      <div class="pricing-modal" id="pricingModal">
        <div class="pricing-dialog">
          <div class="pricing-header">
            <span>Model Pricing ($ per 1M tokens)</span>
            <button class="pricing-close" id="pricingClose">&times;</button>
          </div>
          <div class="pricing-content">
            <div class="pricing-left">
              <div class="pricing-left-title">Available Models</div>
              <div class="pricing-model-list" id="pricingModelList"></div>
            </div>
            <div class="pricing-right">
              <div class="pricing-right-title">Configured Pricing</div>
              <div class="pricing-config-list" id="pricingConfigList"></div>
            </div>
          </div>
          <div class="pricing-footer">
            <button class="btn-now" id="pricingSave">Save</button>
          </div>
        </div>
      </div>

      <div class="pricing-modal" id="sourcesModal">
        <div class="pricing-dialog source-dialog">
          <div class="pricing-header">
            <span>Local Log Sources</span>
            <button class="pricing-close" id="sourcesClose">&times;</button>
          </div>
          <div class="source-content">
            <label class="source-field">
              <span>Claude Code Logs</span>
              <div class="path-input-row">
                <input id="claudePath" type="text" placeholder="~/.claude/projects">
                <button class="btn" id="btnClaudePathOpen">Open Path</button>
              </div>
              <small id="claudeResolved"></small>
            </label>
            <div class="dir-picker source-dir-picker" id="claudeSourceDirPicker">
              <div class="dir-picker-bar">
                <button class="btn" id="btnClaudePathUp">Up</button>
              </div>
              <div class="dir-picker-path">Loading...</div>
              <div class="dir-picker-list"></div>
            </div>
            <label class="source-field">
              <span>Codex Logs</span>
              <div class="path-input-row">
                <input id="codexPath" type="text" placeholder="~/.codex/sessions">
                <button class="btn" id="btnCodexPathOpen">Open Path</button>
              </div>
              <small id="codexResolved"></small>
            </label>
            <div class="dir-picker source-dir-picker" id="codexSourceDirPicker">
              <div class="dir-picker-bar">
                <button class="btn" id="btnCodexPathUp">Up</button>
              </div>
              <div class="dir-picker-path">Loading...</div>
              <div class="dir-picker-list"></div>
            </div>
            <div class="source-status" id="sourcesStatus"></div>
          </div>
          <div class="pricing-footer">
            <button class="btn" id="sourcesCancel">Cancel</button>
            <button class="btn-now" id="sourcesSave">Save</button>
          </div>
        </div>
      </div>

      <div class="hero-counter">
        <div class="hero-label">TOTAL TOKENS</div>
        <div class="hero-digits" id="heroDigits"></div>
      </div>
      <div class="cards" id="summaryCards"></div>
      <div class="layout-top">
        <div class="grid-2">
          <div class="panel full">
            <div class="panel-head"><span class="panel-title">Token Usage Trend</span></div>
            <div class="chart" id="trendChart"></div>
          </div>
        </div>
        <div class="grid-2">
          <div class="panel full">
            <div class="panel-head"><span class="panel-title">Activity Heatmap</span></div>
            <div class="heatmap-wrap" id="heatmapWrap"></div>
          </div>
        </div>
      </div>
      <div class="grid-2">
        <div class="panel full">
          <div class="panel-head">
            <div class="tab-btns tokmon-breakdown-tabs">
              <button class="tbtn active" data-tab="model">By Model</button>
              <button class="tbtn" data-tab="source">By Source</button>
            </div>
          </div>
          <div class="breakdown-grid">
            <div class="chart" id="pieChart"></div>
            <div class="breakdown-table">
              <table class="tbl" id="breakdownTable">
                <thead id="breakdownHead"></thead>
                <tbody></tbody>
              </table>
              <div class="pager" id="pager"></div>
            </div>
          </div>
        </div>
      </div>
      <div class="grid-2">
        <div class="panel full">
          <div class="panel-head"><span class="panel-title">Request Log</span></div>
          <div class="records-table-wrap">
            <table class="tbl" id="recordsTable">
              <thead>
                <tr>
                  <th>Time</th><th>Source</th><th>Model</th>
                  <th class="num">Input</th><th class="num">Output</th>
                  <th class="num">Cache W</th><th class="num">Cache R</th>
                </tr>
              </thead>
              <tbody></tbody>
            </table>
            <div class="pager" id="recordsPager"></div>
            <div class="pager-jump-wrap">
              <span class="pager-info" id="recordsPageInfo"></span>
              <input class="pager-jump" id="recordsJump" type="number" min="1" placeholder="Go">
            </div>
          </div>
        </div>
      </div>
    </div>
  `;
  tokmonInstance = window.AgentMonTokMon?.mount(document.getElementById('tokmonView')) || null;
}

function renderTokensHeaderActions() {
  $headerActions().innerHTML = `
    <div class="tokens-control-wrap" data-tokmon-global>
      <button class="tokens-control-trigger" id="btnTokensControls" aria-label="Tokens controls" aria-expanded="false">
        <span>Controls</span>
        <span class="tokens-control-caret">▾</span>
      </button>
      <div class="tokens-control-menu" id="tokensControlMenu">
        <div class="tokens-control-section">
          <div class="tokens-control-title">Scope</div>
          <select id="source">
            <option value="">All Sources</option>
            <option value="claude-code">Claude Code</option>
            <option value="codex">Codex</option>
          </select>
        </div>
        <div class="tokens-control-section">
          <div class="tokens-control-title">Range</div>
          <div class="range-btns tokens-range-grid">
            <button class="rbtn" data-hours="1">1H</button>
            <button class="rbtn" data-hours="3">3H</button>
            <button class="rbtn" data-hours="6">6H</button>
            <button class="rbtn" data-hours="12">12H</button>
            <button class="rbtn" data-days="1">1D</button>
            <button class="rbtn" data-days="3">3D</button>
            <button class="rbtn active" data-days="7">7D</button>
            <button class="rbtn" data-days="30">30D</button>
            <button class="rbtn" data-days="90">90D</button>
          </div>
          <div class="tokens-date-grid">
            <input type="datetime-local" id="dateFrom">
            <input type="datetime-local" id="dateTo">
            <button class="btn-now" id="btnNow">Now ●</button>
          </div>
        </div>
        <div class="tokens-control-section">
          <div class="tokens-control-title">Options</div>
          <label>Granularity
            <div class="range-btns tokens-segmented">
              <button class="rbtn" id="btnHourly" data-interval="hour">Hourly</button>
              <button class="rbtn active" id="btnDaily" data-interval="day">Daily</button>
            </div>
          </label>
          <label>Refresh
            <select id="refreshRate">
              <option value="1000">1s</option>
              <option value="3000" selected>3s</option>
              <option value="5000">5s</option>
              <option value="10000">10s</option>
              <option value="30000">30s</option>
              <option value="60000">60s</option>
              <option value="0">Off</option>
            </select>
          </label>
          <label>Range Mode
            <div class="range-btns tokens-segmented">
              <button class="rbtn active" id="btnExact" data-mode="exact">Exact</button>
              <button class="rbtn" id="btnRound" data-mode="round">Round</button>
            </div>
          </label>
        </div>
        <div class="tokens-control-section">
          <div class="tokens-control-title">Configuration</div>
          <button class="btn-pricing" id="btnSources">Configure Sources</button>
          <button class="btn-pricing" id="btnPricing">Configure Models</button>
        </div>
      </div>
    </div>
  `;
}

function renderSessionsHeaderActions() {
  const archived = sessionsFilters.archived === '1';
  $headerActions().innerHTML = `
    <div class="session-status-switch range-btns" aria-label="Session status filter">
      <button class="rbtn ${archived ? '' : 'active'}" data-archived="0">Active</button>
      <button class="rbtn ${archived ? 'active' : ''}" data-archived="1">Archived</button>
    </div>
  `;
  $headerActions().querySelectorAll('[data-archived]').forEach(btn => {
    btn.addEventListener('click', () => {
      const next = btn.dataset.archived;
      if (sessionsFilters.archived === next) return;
      sessionsFilters.archived = next;
      sessionsPage = 1;
      selectedSessionIds.clear();
      renderSessions();
    });
  });
}

function clearHeaderActions() {
  $headerActions().innerHTML = '';
}

function destroyTokMon() {
  if (!tokmonInstance) return;
  tokmonInstance.destroy?.();
  tokmonInstance = null;
}

/* ── Sessions View ── */
async function renderSessions() {
  renderSessionsHeaderActions();
  const f = sessionsFilters;
  const params = new URLSearchParams({ page: sessionsPage, limit: sessionsPageSize });
  if (f.source) params.set('source', f.source);
  if (f.q) params.set('q', f.q);
  params.set('archived', f.archived);

  const data = await api('/sessions?' + params);
  const rows = data.rows || [];
  const total = data.total || 0;
  const pages = Math.ceil(total / sessionsPageSize);
  const selectedCount = rows.filter(r => selectedSessionIds.has(r.id)).length;
  const batchLabel = f.archived === '1' ? 'Restore Selected' : 'Archive Selected';

  $content().innerHTML = `
    <div class="filters">
      <select id="fSource"><option value="">All Sources</option><option value="claude-code">Claude Code</option><option value="codex">Codex</option></select>
      <input id="fSearch" placeholder="Search project, model, prompt..." value="${esc(f.q)}">
      <button class="btn ${sessionsManageMode ? 'btn-accent' : ''}" id="btnManageSessions">${sessionsManageMode ? 'Exit Manage' : 'Manage'}</button>
      ${sessionsManageMode ? `
        <div class="manage-inline">
          <label class="manage-check-all"><input type="checkbox" id="checkAllSessions" ${rows.length > 0 && selectedCount === rows.length ? 'checked' : ''}> Select page</label>
          <span class="manage-count">${selectedSessionIds.size} selected</span>
          <button class="btn" id="btnMigrateProject" ${selectedSessionIds.size ? '' : 'disabled'}>Migrate Project</button>
          <button class="btn" id="btnBatchArchive" ${selectedSessionIds.size ? '' : 'disabled'}>${batchLabel}</button>
          <button class="btn btn-danger" id="btnBatchDelete" ${selectedSessionIds.size ? '' : 'disabled'}>Delete Selected</button>
          <button class="btn" id="btnClearSelection" ${selectedSessionIds.size ? '' : 'disabled'}>Clear</button>
        </div>
      ` : ''}
    </div>
    <div class="panel">
      ${rows.length === 0 ? '<div class="empty">No sessions found</div>' : `
      <table class="tbl sessions-table ${sessionsManageMode ? 'manage-mode' : ''}">
        <thead><tr>
          <th class="check-col"></th>
          <th>Source</th><th>Project</th><th class="prompt-th">${showLastPrompt ? 'Last Prompt' : 'First Prompt'} <button class="btn-switch-prompt" id="btnSwitchPrompt">${showLastPrompt ? '← first' : 'last →'}</button></th><th>Model</th><th>Msgs</th><th>Last Active</th><th>Status</th>
        </tr></thead>
        <tbody>${rows.map(r => `
          <tr data-id="${esc(r.id)}" class="${selectedSessionIds.has(r.id) ? 'row-selected' : ''}">
            <td class="check-col">${sessionsManageMode ? `<input type="checkbox" class="session-check" data-id="${esc(r.id)}" ${selectedSessionIds.has(r.id) ? 'checked' : ''}>` : ''}</td>
            <td>${sourceBadge(r.source)}</td>
            <td class="muted">${esc(trunc(r.project_path?.split('/').pop(), 20))}</td>
            <td class="prompt-cell">${esc(trunc(showLastPrompt ? (r.last_prompt || r.first_prompt) : r.first_prompt, 50))}</td>
            <td>${esc(r.model || '?')}</td>
            <td>${r.message_count}</td>
            <td class="muted">${relTime(r.last_active_at)}</td>
            <td>${r.is_active ? '<span class="badge badge-active">Live</span>' : ''}${r.archived ? '<span class="badge badge-archived">Archived</span>' : ''}</td>
          </tr>`).join('')}
        </tbody>
      </table>`}
      ${pages > 1 ? `<div class="pager">${Array.from({length: pages}, (_, i) => `<button class="${i + 1 === sessionsPage ? 'active' : ''}" data-page="${i + 1}">${i + 1}</button>`).join('')}</div>` : ''}
      <div class="pager"><span class="pager-info">${total} total</span><select id="fPageSize">${[10,15,25,50].map(n => `<option value="${n}" ${n === sessionsPageSize ? 'selected' : ''}>${n} / page</option>`).join('')}</select></div>
    </div>`;

  $('#fSource').value = f.source;

  document.getElementById('fPageSize')?.addEventListener('change', (e) => {
    sessionsPageSize = parseInt(e.target.value, 10);
    sessionsPage = 1;
    renderSessions();
  });

  document.getElementById('btnSwitchPrompt')?.addEventListener('click', () => {
    showLastPrompt = !showLastPrompt;
    renderSessions();
  });

  for (const id of ['fSource', 'fSearch']) {
    const el = document.getElementById(id);
    el.addEventListener('change', () => {
      sessionsFilters = {
        source: $('#fSource').value, project: '', model: '',
        q: $('#fSearch').value, archived: sessionsFilters.archived,
      };
      sessionsPage = 1;
      selectedSessionIds.clear();
      renderSessions();
    });
  }

  document.getElementById('btnManageSessions')?.addEventListener('click', () => {
    sessionsManageMode = !sessionsManageMode;
    if (!sessionsManageMode) selectedSessionIds.clear();
    renderSessions();
  });

  $content().querySelectorAll('.pager button').forEach(btn => {
    btn.addEventListener('click', () => { sessionsPage = +btn.dataset.page; renderSessions(); });
  });

  $content().querySelectorAll('tr[data-id]').forEach(tr => {
    tr.addEventListener('click', (e) => {
      const id = tr.dataset.id;
      if (e.target.closest('.prompt-cell')) {
        showSessionDetail(id);
        return;
      }
      if (sessionsManageMode) {
        if (e.target.closest('input')) return;
        if (selectedSessionIds.has(id)) selectedSessionIds.delete(id);
        else selectedSessionIds.add(id);
        renderSessions();
        return;
      }
    });
  });

  $content().querySelectorAll('.session-check').forEach(input => {
    input.addEventListener('change', () => {
      const id = input.dataset.id;
      if (input.checked) selectedSessionIds.add(id);
      else selectedSessionIds.delete(id);
      renderSessions();
    });
  });

  document.getElementById('checkAllSessions')?.addEventListener('change', (e) => {
    if (e.target.checked) rows.forEach(r => selectedSessionIds.add(r.id));
    else rows.forEach(r => selectedSessionIds.delete(r.id));
    renderSessions();
  });

  document.getElementById('btnClearSelection')?.addEventListener('click', () => {
    selectedSessionIds.clear();
    renderSessions();
  });

  document.getElementById('btnBatchArchive')?.addEventListener('click', async () => {
    const archived = f.archived === '1' ? 0 : 1;
    for (const id of selectedSessionIds) {
      await api('/sessions/' + id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ archived }) });
    }
    selectedSessionIds.clear();
    renderSessions();
  });

  document.getElementById('btnBatchDelete')?.addEventListener('click', async () => {
    if (!selectedSessionIds.size) return;
    if (!confirm(`Permanently delete ${selectedSessionIds.size} session(s) and their files?`)) return;
    for (const id of selectedSessionIds) {
      await api('/sessions/' + id, { method: 'DELETE' });
    }
    selectedSessionIds.clear();
    renderSessions();
  });

  document.getElementById('btnMigrateProject')?.addEventListener('click', () => {
    if (!selectedSessionIds.size) return;
    openMigrateProjectModal();
  });
}

function openMigrateProjectModal() {
  const count = selectedSessionIds.size;
  openModal(`
    <div class="modal-fixed migrate-project-modal">
    <h3>Migrate Project</h3>
    <label>Target Project Path
      <div class="path-input-row">
        <input id="migrateProjectPath" placeholder="/path/to/new-project">
        <button class="btn" id="btnDirOpen">Open Path</button>
      </div>
    </label>
    <div class="dir-picker" id="migrateDirPicker">
      <div class="dir-picker-bar">
        <button class="btn" id="btnDirUp">Up</button>
      </div>
      <div class="dir-picker-path" id="dirPickerPath">Loading...</div>
      <div class="dir-picker-list" id="dirPickerList"></div>
    </div>
    <div class="modal-note">
      This updates selected session metadata and rewrites the original JSONL files. Claude Code sessions are also moved into the matching project directory.
    </div>
    <div class="modal-status" id="migrateStatus"></div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn btn-accent" id="btnDoMigrateProject">Migrate ${count}</button>
    </div>
    </div>
  `);

  document.getElementById('btnDoMigrateProject')?.addEventListener('click', async () => {
    const projectPath = $('#migrateProjectPath').value.trim();
    const status = $('#migrateStatus');
    if (!projectPath) {
      status.textContent = 'Target project path is required.';
      status.className = 'modal-status error';
      return;
    }
    if (!confirm(`Migrate ${count} selected session(s) to:\n${projectPath}\n\nThis will modify local session files.`)) return;

    const btn = document.getElementById('btnDoMigrateProject');
    btn.disabled = true;
    status.textContent = 'Migrating...';
    status.className = 'modal-status';
    try {
      const res = await fetch('/api/sessions/migrate-project', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: Array.from(selectedSessionIds), projectPath }),
      });
      const data = await res.json();
      if (!res.ok && res.status !== 207) throw new Error(data.error || 'Migration failed');
      if (data.errors?.length) {
        status.textContent = `Migrated ${data.migratedCount || 0}; ${data.errors.length} failed.`;
        status.className = 'modal-status error';
        return;
      }
      selectedSessionIds.clear();
      sessionsPage = 1;
      closeModal();
      renderSessions();
    } catch (err) {
      status.textContent = err.message || 'Migration failed.';
      status.className = 'modal-status error';
    } finally {
      btn.disabled = false;
    }
  });

  initDirectoryPicker({
    input: '#migrateProjectPath',
    openButton: '#btnDirOpen',
    upButton: '#btnDirUp',
    root: '#migrateDirPicker',
    initialPath: sessionsFilters.project.startsWith('/') ? sessionsFilters.project : '~',
    showHidden: true,
  });
}

async function initDirectoryPicker(options) {
  let currentPath = options.initialPath || '~';
  const input = document.querySelector(options.input);
  const openButton = document.querySelector(options.openButton);
  const upButton = document.querySelector(options.upButton);
  const root = document.querySelector(options.root);
  const pathEl = root?.querySelector('.dir-picker-path');
  const listEl = root?.querySelector('.dir-picker-list');
  if (!input || !openButton || !upButton || !root || !pathEl || !listEl) return;
  if (root._agentMonDirPickerCleanup) root._agentMonDirPickerCleanup.forEach(fn => fn());
  const cleanup = [];
  const onDirPicker = (target, type, handler, options) => {
    target.addEventListener(type, handler, options);
    cleanup.push(() => target.removeEventListener(type, handler, options));
  };

  async function loadDir(path) {
    pathEl.textContent = 'Loading...';
    listEl.innerHTML = '';
    try {
      const data = await api('/sessions/directories?path=' + encodeURIComponent(path) + (options.showHidden ? '&showHidden=1' : ''));
      if (data.error) throw new Error(data.error);
      currentPath = data.path;
      input.value = data.path;
      pathEl.textContent = data.path;
      listEl.innerHTML = data.entries.length
        ? data.entries.map(entry => `<button class="dir-picker-item" data-path="${esc(entry.path)}">${esc(entry.name)}</button>`).join('')
        : '<div class="dir-picker-empty">No child directories</div>';
    } catch (err) {
      pathEl.textContent = err.message || 'Failed to read directory';
      listEl.innerHTML = '';
    }
  }

  onDirPicker(upButton, 'click', () => {
    const parts = currentPath.split('/').filter(Boolean);
    loadDir('/' + parts.slice(0, -1).join('/'));
  });
  onDirPicker(openButton, 'click', () => loadDir(input.value.trim() || currentPath));
  onDirPicker(listEl, 'click', (e) => {
    const item = e.target.closest('[data-path]');
    if (item) loadDir(item.dataset.path);
  });
  onDirPicker(listEl, 'wheel', (e) => {
    const canScroll = listEl.scrollHeight > listEl.clientHeight;
    if (!canScroll) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }
    const atTop = listEl.scrollTop <= 0;
    const atBottom = listEl.scrollTop + listEl.clientHeight >= listEl.scrollHeight - 1;
    if ((e.deltaY < 0 && atTop) || (e.deltaY > 0 && atBottom)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, { passive: false });
  root._agentMonDirPickerCleanup = cleanup;

  loadDir(currentPath);
}
window.AgentMonDirectoryPicker = initDirectoryPicker;

async function showSessionDetail(id) {
  const data = await api('/sessions/' + id + '?limit=99999');
  const msgs = data.messages || [];
  openModal(`
    <h3>${sourceBadge(data.source)} ${esc(trunc((showLastPrompt ? data.last_prompt : data.first_prompt) || data.first_prompt, 60))}</h3>
    <div style="font-family:var(--font-mono);font-size:0.72rem;color:var(--text-muted);margin-bottom:12px;">
      <div>ID: ${esc(data.id)}</div>
      <div>Model: <span>${esc(data.model || '?')}</span></div>
      <div>Project: ${esc(data.project_path || '?')}</div>
      <div>Messages: ${data.message_count} | Started: ${relTime(data.started_at)}</div>
      ${data.tags && data.tags !== '[]' ? '<div>Tags: ' + JSON.parse(data.tags).map(t => '<span class="tag">' + esc(t) + '</span>').join('') + '</div>' : ''}
    </div>
    <div class="msg-scroll-btns">
      <button class="btn" id="msgScrollTop">Top</button>
      <button class="btn" id="msgScrollBottom">Bottom</button>
    </div>
    <div class="msg-list" id="msgList">${msgs.length === 0 ? '<div class="empty">No messages</div>' : msgs.map(m => `
      <div class="msg">
        <div class="msg-role ${m.type}">${m.type}</div>
        <div class="msg-text">${esc(trunc(m.text, 500))}</div>
        <div class="msg-time">${relTime(m.timestamp)}</div>
      </div>`).join('')}
    </div>
  `);

  const list = document.getElementById('msgList');
  document.getElementById('msgScrollTop')?.addEventListener('click', () => { if (list) list.scrollTop = 0; });
  document.getElementById('msgScrollBottom')?.addEventListener('click', () => { if (list) list.scrollTop = list.scrollHeight; });
}

/* ── Skills View ── */
let selectedSkillName = null;
async function renderSkills() {
  const skills = await api('/skills');

  const prevScroll = $content().querySelector('.split-list')?.scrollTop ?? 0;

  const skillsByName = {};
  const uniqueSkills = [];
  const seenNames = new Set();
  for (const s of skills) {
    if (!skillsByName[s.name]) skillsByName[s.name] = {};
    skillsByName[s.name][s.source] = s;
    if (!seenNames.has(s.name)) {
      seenNames.add(s.name);
      uniqueSkills.push(s);
    }
  }
  const skillQuery = skillsSearch.trim().toLowerCase();
  const visibleSkills = skillQuery
    ? uniqueSkills.filter(s => {
        const peers = skillsByName[s.name] || {};
        const haystack = [s.name, s.description, s.path, s.symlink_target, ...Object.keys(peers)].filter(Boolean).join(' ').toLowerCase();
        return haystack.includes(skillQuery);
      })
    : uniqueSkills;

  if (selectedSkillName && !visibleSkills.some(s => s.name === selectedSkillName)) selectedSkillName = visibleSkills[0]?.name ?? null;
  selectedSkillName = selectedSkillName || (visibleSkills[0]?.name ?? null);
  const peerMap = selectedSkillName ? (skillsByName[selectedSkillName] || {}) : {};
  const detail = peerMap['claude-code'] || peerMap['codex'] || null;
  const isBroken = detail && detail.description && detail.description.startsWith('Broken symlink');
  const brokenCount = skills.filter(s => (s.description || '').startsWith('Broken symlink')).length;
  const ccInstalled = !!peerMap['claude-code'];
  const codexInstalled = !!peerMap['codex'];
  const realTarget = detail ? (detail.symlink_target || detail.path) : '';
  const selectedSkillCount = visibleSkills.filter(s => selectedSkillNames.has(s.name)).length;

  function platformPillsHtml() {
    if (!detail || isBroken) return '';
    return `<div class="platform-pills">
      <span class="pill-label">Installed on:</span>
      <span class="platform-pill ${ccInstalled ? 'installed' : 'not-installed'}" data-platform="claude-code">
        <span class="pill-dot"></span>Claude Code
      </span>
      <span class="platform-pill ${codexInstalled ? 'installed' : 'not-installed'}" data-platform="codex">
        <span class="pill-dot"></span>Codex
      </span>
    </div>`;
  }

  $content().innerHTML = `
    <div class="filters">
      <button class="btn btn-accent" id="btnInstallSkill">+ Install Skill</button>
      ${brokenCount > 0 ? `<button class="btn btn-danger" id="btnCleanupBroken">Clean ${brokenCount} broken</button>` : ''}
      <input id="skillSearch" placeholder="Search skills..." value="${esc(skillsSearch)}">
      <button class="btn ${skillsManageMode ? 'btn-accent' : ''}" id="btnManageSkills">${skillsManageMode ? 'Exit Manage' : 'Manage'}</button>
      ${skillsManageMode ? `
        <div class="manage-inline">
          <label class="manage-check-all"><input type="checkbox" id="checkAllSkills" ${visibleSkills.length > 0 && selectedSkillCount === visibleSkills.length ? 'checked' : ''}> Select all</label>
          <span class="manage-count">${selectedSkillNames.size} selected</span>
          <button class="btn btn-danger" id="btnBatchDeleteSkills" ${selectedSkillNames.size ? '' : 'disabled'}>Uninstall Selected</button>
          <button class="btn" id="btnClearSkillSelection" ${selectedSkillNames.size ? '' : 'disabled'}>Clear</button>
        </div>
      ` : ''}
    </div>
    <div class="split-layout">
      <div class="panel split-list" id="skillList">${visibleSkills.length === 0 ? '<div class="empty">No skills</div>' : visibleSkills.map(s => {
        const broken = s.description && s.description.startsWith('Broken symlink');
        const peers = skillsByName[s.name] || {};
        const platforms = Object.keys(peers);
        return `
        <div class="split-item ${skillsManageMode ? 'with-check' : ''} ${s.name === selectedSkillName ? 'active' : ''} ${selectedSkillNames.has(s.name) ? 'row-selected' : ''}" data-name="${esc(s.name)}">
          ${skillsManageMode ? `<input type="checkbox" class="split-check skill-check" data-name="${esc(s.name)}" ${selectedSkillNames.has(s.name) ? 'checked' : ''}>` : ''}
          <div class="split-item-body">
            <div class="split-item-name">${platforms.map(p => sourceBadge(p)).join(' ')} ${esc(s.name)}</div>
            <div class="split-item-meta">${broken ? '<span class="red">broken</span>' : s.enabled ? '<span class="green">enabled</span>' : '<span class="muted">disabled</span>'} · ${esc(s.is_symlink ? 'symlink' : 'local')}</div>
          </div>
        </div>`;
      }).join('')}
      </div>
      <div class="panel">${!detail ? '<div class="empty">Select a skill</div>' : `
        <div class="detail-header">
          <div class="detail-title">${esc(detail.name)}</div>
          <div class="detail-actions">
            ${isBroken ? '' : `<label class="toggle"><input type="checkbox" id="toggleSkill" ${detail.enabled ? 'checked' : ''}><span class="toggle-slider"></span></label>`}
          </div>
        </div>
        <div style="font-family:var(--font-mono);font-size:0.72rem;color:var(--text-muted);margin-bottom:8px;">
          ${esc(detail.is_symlink ? 'symlink' : 'local')}
        </div>
        ${platformPillsHtml()}
        ${detail.description ? '<div style="color:var(--text-muted);font-size:0.82rem;margin-bottom:8px;">' + (isBroken ? '<span class="red">' + esc(detail.description) + '</span>' : esc(detail.description)) + '</div>' : ''}
        ${detail.skill_md ? '<div class="skill-md">' + esc(detail.skill_md) + '</div>' : (!isBroken ? '' : '<div class="empty">Symlink target does not exist</div>')}
      `}</div>
    </div>`;

  const listEl = document.getElementById('skillList');
  if (listEl) listEl.scrollTop = prevScroll;

  document.getElementById('skillSearch')?.addEventListener('input', (e) => {
    skillsSearch = e.target.value;
    renderSkills();
  });

  document.getElementById('btnManageSkills')?.addEventListener('click', () => {
    skillsManageMode = !skillsManageMode;
    if (!skillsManageMode) selectedSkillNames.clear();
    renderSkills();
  });

  document.getElementById('checkAllSkills')?.addEventListener('change', (e) => {
    if (e.target.checked) visibleSkills.forEach(s => selectedSkillNames.add(s.name));
    else visibleSkills.forEach(s => selectedSkillNames.delete(s.name));
    renderSkills();
  });

  document.getElementById('btnClearSkillSelection')?.addEventListener('click', () => {
    selectedSkillNames.clear();
    renderSkills();
  });

  document.getElementById('btnBatchDeleteSkills')?.addEventListener('click', async () => {
    if (!selectedSkillNames.size) return;
    if (!confirm(`Uninstall ${selectedSkillNames.size} selected skill(s) from all installed platforms?`)) return;
    for (const name of selectedSkillNames) {
      const peers = skillsByName[name] || {};
      for (const peer of Object.values(peers)) {
        await api('/skills/' + encodeURIComponent(peer.id), { method: 'DELETE' });
      }
    }
    selectedSkillNames.clear();
    selectedSkillName = null;
    renderSkills();
  });

  $content().querySelectorAll('.platform-pill').forEach(pill => {
    pill.addEventListener('click', async () => {
      const platform = pill.dataset.platform;
      const isInstalled = pill.classList.contains('installed');
      const bothInstalled = ccInstalled && codexInstalled;
      if (isInstalled) {
        if (!bothInstalled) { alert('At least one platform must have this skill installed.'); return; }
        const peerId = platform + ':' + detail.name;
        await api('/skills/' + encodeURIComponent(peerId), { method: 'DELETE' });
      } else {
        await api('/skills', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ source: platform, name: detail.name, targetPath: realTarget }) });
      }
      renderSkills();
    });
  });

  $content().querySelectorAll('.split-item').forEach(el => {
    el.addEventListener('click', (e) => {
      const name = el.dataset.name;
      if (skillsManageMode) {
        if (e.target.closest('input')) return;
        if (selectedSkillNames.has(name)) selectedSkillNames.delete(name);
        else selectedSkillNames.add(name);
        renderSkills();
        return;
      }
      selectedSkillName = name;
      renderSkills();
    });
  });

  $content().querySelectorAll('.skill-check').forEach(input => {
    input.addEventListener('change', () => {
      const name = input.dataset.name;
      if (input.checked) selectedSkillNames.add(name);
      else selectedSkillNames.delete(name);
      renderSkills();
    });
  });

  const toggleEl = document.getElementById('toggleSkill');
  if (toggleEl) {
    toggleEl.addEventListener('change', async () => {
      await api('/skills/' + encodeURIComponent(detail.id), { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled: toggleEl.checked }) });
      renderSkills();
    });
  }

  document.getElementById('btnCleanupBroken')?.addEventListener('click', async () => {
    if (!confirm(`Remove ${brokenCount} broken symlink skill(s)?`)) return;
    const result = await api('/skills/cleanup-broken', { method: 'POST' });
    selectedSkillName = null;
    renderSkills();
  });

  document.getElementById('btnInstallSkill')?.addEventListener('click', () => {
    openModal(`
      <div class="modal-fixed install-skill-modal">
      <h3>Install Skill</h3>
      <div class="install-targets">
        <div class="install-target-label">Install To</div>
        <button class="install-target selected" data-source="claude-code" type="button"><span class="pill-dot"></span>Claude Code</button>
        <button class="install-target selected" data-source="codex" type="button"><span class="pill-dot"></span>Codex</button>
      </div>
      <label>Name<input id="installName" placeholder="skill-name"></label>
      <label>Target Path
        <div class="path-input-row">
          <input id="installPath" placeholder="/path/to/skill">
          <button class="btn" id="btnInstallDirOpen">Open Path</button>
        </div>
      </label>
      <div class="dir-picker" id="installDirPicker">
        <div class="dir-picker-bar">
          <button class="btn" id="btnInstallDirUp">Up</button>
        </div>
        <div class="dir-picker-path">Loading...</div>
        <div class="dir-picker-list"></div>
      </div>
      <div class="modal-status" id="installStatus"></div>
      <div class="modal-actions"><button class="btn" onclick="closeModal()">Cancel</button><button class="btn btn-accent" id="btnDoInstall">Install</button></div>
      </div>
    `);
    initDirectoryPicker({
      input: '#installPath',
      openButton: '#btnInstallDirOpen',
      upButton: '#btnInstallDirUp',
      root: '#installDirPicker',
      initialPath: '~',
      showHidden: true,
    });
    document.querySelectorAll('.install-target').forEach(btn => {
      btn.addEventListener('click', () => btn.classList.toggle('selected'));
    });
    document.getElementById('btnDoInstall').addEventListener('click', async () => {
      const sources = Array.from(document.querySelectorAll('.install-target.selected')).map(btn => btn.dataset.source);
      const name = $('#installName').value.trim();
      const targetPath = $('#installPath').value.trim();
      const status = $('#installStatus');
      if (!sources.length) { status.textContent = 'Select at least one install target.'; status.className = 'modal-status error'; return; }
      if (!name || !targetPath) { status.textContent = 'Name and target path are required.'; status.className = 'modal-status error'; return; }
      const btn = document.getElementById('btnDoInstall');
      btn.disabled = true;
      status.textContent = 'Installing...';
      status.className = 'modal-status';
      try {
        for (const source of sources) {
          const result = await api('/skills', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ source, name, targetPath }) });
          if (result.error) throw new Error(`${source}: ${result.error}`);
        }
      } catch (err) {
        status.textContent = err.message || 'Install failed.';
        status.className = 'modal-status error';
        btn.disabled = false;
        return;
      }
      closeModal();
      renderSkills();
    });
  });
}

/* ── MCP View ── */
let selectedMcpName = null;
async function renderMcp() {
  const items = await api('/mcp');
  const prevScroll = $content().querySelector('.split-list')?.scrollTop ?? 0;

  const mcpByName = {};
  const uniqueMcp = [];
  const seenMcpNames = new Set();
  for (const m of items) {
    if (!mcpByName[m.name]) mcpByName[m.name] = {};
    mcpByName[m.name][m.source] = m;
    if (!seenMcpNames.has(m.name)) {
      seenMcpNames.add(m.name);
      uniqueMcp.push(m);
    }
  }
  const mcpQuery = mcpSearch.trim().toLowerCase();
  const visibleMcp = mcpQuery
    ? uniqueMcp.filter(m => {
        const peers = mcpByName[m.name] || {};
        const peerValues = Object.values(peers).flatMap(peer => [peer.url, peer.command, peer.args, peer.config_raw]);
        const haystack = [m.name, m.url, m.command, m.args, m.config_raw, ...Object.keys(peers), ...peerValues].filter(Boolean).join(' ').toLowerCase();
        return haystack.includes(mcpQuery);
      })
    : uniqueMcp;

  if (selectedMcpName && !visibleMcp.some(m => m.name === selectedMcpName)) selectedMcpName = visibleMcp[0]?.name ?? null;
  selectedMcpName = selectedMcpName || (visibleMcp[0]?.name ?? null);
  const mcpPeerMap = selectedMcpName ? (mcpByName[selectedMcpName] || {}) : {};
  const detail = mcpPeerMap['claude-code'] || mcpPeerMap['codex'] || null;
  const mcpCcInstalled = !!mcpPeerMap['claude-code'];
  const mcpCodexInstalled = !!mcpPeerMap['codex'];
  const selectedMcpCount = visibleMcp.filter(m => selectedMcpNames.has(m.name)).length;

  function mcpPlatformPillsHtml() {
    if (!detail) return '';
    return `<div class="platform-pills">
      <span class="pill-label">Installed on:</span>
      <span class="platform-pill ${mcpCcInstalled ? 'installed' : 'not-installed'}" data-platform="claude-code">
        <span class="pill-dot"></span>Claude Code
      </span>
      <span class="platform-pill ${mcpCodexInstalled ? 'installed' : 'not-installed'}" data-platform="codex">
        <span class="pill-dot"></span>Codex
      </span>
    </div>`;
  }

  $content().innerHTML = `
    <div class="filters">
      <button class="btn btn-accent" id="btnAddMcp">+ Add MCP Server</button>
      <input id="mcpSearch" placeholder="Search MCP..." value="${esc(mcpSearch)}">
      <button class="btn ${mcpManageMode ? 'btn-accent' : ''}" id="btnManageMcp">${mcpManageMode ? 'Exit Manage' : 'Manage'}</button>
      ${mcpManageMode ? `
        <div class="manage-inline">
          <label class="manage-check-all"><input type="checkbox" id="checkAllMcp" ${visibleMcp.length > 0 && selectedMcpCount === visibleMcp.length ? 'checked' : ''}> Select all</label>
          <span class="manage-count">${selectedMcpNames.size} selected</span>
          <button class="btn btn-danger" id="btnBatchDeleteMcp" ${selectedMcpNames.size ? '' : 'disabled'}>Delete Selected</button>
          <button class="btn" id="btnClearMcpSelection" ${selectedMcpNames.size ? '' : 'disabled'}>Clear</button>
        </div>
      ` : ''}
    </div>
    <div class="split-layout">
      <div class="panel split-list" id="mcpList">${visibleMcp.length === 0 ? '<div class="empty">No MCP servers</div>' : visibleMcp.map(m => {
        const mcpPeers = mcpByName[m.name] || {};
        const mcpPlatforms = Object.keys(mcpPeers);
        return `
        <div class="split-item ${mcpManageMode ? 'with-check' : ''} ${m.name === selectedMcpName ? 'active' : ''} ${selectedMcpNames.has(m.name) ? 'row-selected' : ''}" data-name="${esc(m.name)}">
          ${mcpManageMode ? `<input type="checkbox" class="split-check mcp-check" data-name="${esc(m.name)}" ${selectedMcpNames.has(m.name) ? 'checked' : ''}>` : ''}
          <div class="split-item-body">
            <div class="split-item-name">${mcpPlatforms.map(p => sourceBadge(p)).join(' ')} ${esc(m.name)}</div>
            <div class="split-item-meta">${esc(m.url || m.command || '')}</div>
          </div>
        </div>`;
      }).join('')}
      </div>
      <div class="panel">${!detail ? '<div class="empty">Select an MCP server</div>' : `
        <div class="detail-header">
          <div class="detail-title">${esc(detail.name)}</div>
          <div class="detail-actions">
            <label class="toggle"><input type="checkbox" id="toggleMcp" ${detail.enabled ? 'checked' : ''}><span class="toggle-slider"></span></label>
          </div>
        </div>
        <div style="font-family:var(--font-mono);font-size:0.72rem;color:var(--text-muted);line-height:1.8;">
          <div>URL: ${esc(detail.url || '-')}</div>
          <div>Command: ${esc(detail.command || '-')}</div>
          <div>Args: ${esc(detail.args || '-')}</div>
        </div>
        ${mcpPlatformPillsHtml()}
        ${detail.config_raw ? '<div class="skill-md">' + esc(detail.config_raw) + '</div>' : ''}
      `}</div>
    </div>`;

  const mcpListEl = document.getElementById('mcpList');
  if (mcpListEl) mcpListEl.scrollTop = prevScroll;

  document.getElementById('mcpSearch')?.addEventListener('input', (e) => {
    mcpSearch = e.target.value;
    renderMcp();
  });

  document.getElementById('btnManageMcp')?.addEventListener('click', () => {
    mcpManageMode = !mcpManageMode;
    if (!mcpManageMode) selectedMcpNames.clear();
    renderMcp();
  });

  document.getElementById('checkAllMcp')?.addEventListener('change', (e) => {
    if (e.target.checked) visibleMcp.forEach(m => selectedMcpNames.add(m.name));
    else visibleMcp.forEach(m => selectedMcpNames.delete(m.name));
    renderMcp();
  });

  document.getElementById('btnClearMcpSelection')?.addEventListener('click', () => {
    selectedMcpNames.clear();
    renderMcp();
  });

  document.getElementById('btnBatchDeleteMcp')?.addEventListener('click', async () => {
    if (!selectedMcpNames.size) return;
    if (!confirm(`Delete ${selectedMcpNames.size} selected MCP server(s) from all installed platforms?`)) return;
    for (const name of selectedMcpNames) {
      const peers = mcpByName[name] || {};
      for (const peer of Object.values(peers)) {
        await api('/mcp/' + encodeURIComponent(peer.id), { method: 'DELETE' });
      }
    }
    selectedMcpNames.clear();
    selectedMcpName = null;
    renderMcp();
  });

  $content().querySelectorAll('.platform-pill').forEach(pill => {
    pill.addEventListener('click', async () => {
      const platform = pill.dataset.platform;
      const isInstalled = pill.classList.contains('installed');
      const bothInstalled = mcpCcInstalled && mcpCodexInstalled;
      if (isInstalled) {
        if (!bothInstalled) { alert('At least one platform must have this MCP server.'); return; }
        const peerId = platform + ':' + detail.name;
        await api('/mcp/' + encodeURIComponent(peerId), { method: 'DELETE' });
      } else {
        const body = { source: platform, name: detail.name };
        if (detail.url) body.url = detail.url;
        if (detail.command) body.command = detail.command;
        if (detail.args) { try { body.args = JSON.parse(detail.args); } catch {} }
        await api('/mcp', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      }
      renderMcp();
    });
  });

  $content().querySelectorAll('.split-item').forEach(el => {
    el.addEventListener('click', (e) => {
      const name = el.dataset.name;
      if (mcpManageMode) {
        if (e.target.closest('input')) return;
        if (selectedMcpNames.has(name)) selectedMcpNames.delete(name);
        else selectedMcpNames.add(name);
        renderMcp();
        return;
      }
      selectedMcpName = name;
      renderMcp();
    });
  });

  $content().querySelectorAll('.mcp-check').forEach(input => {
    input.addEventListener('change', () => {
      const name = input.dataset.name;
      if (input.checked) selectedMcpNames.add(name);
      else selectedMcpNames.delete(name);
      renderMcp();
    });
  });

  document.getElementById('toggleMcp')?.addEventListener('change', async (e) => {
    await api('/mcp/' + encodeURIComponent(detail.id), { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled: e.target.checked }) });
    renderMcp();
  });

  document.getElementById('btnAddMcp')?.addEventListener('click', () => {
    openModal(`
      <h3>Add MCP Server</h3>
      <div class="install-targets">
        <div class="install-target-label">Add To</div>
        <button class="install-target selected" data-source="claude-code" type="button"><span class="pill-dot"></span>Claude Code</button>
        <button class="install-target selected" data-source="codex" type="button"><span class="pill-dot"></span>Codex</button>
      </div>
      <label>Name<input id="mcpName" placeholder="server-name"></label>
      <label>URL<input id="mcpUrl" placeholder="https://..."></label>
      <label>Command<input id="mcpCommand" placeholder="optional"></label>
      <label>Args<input id="mcpArgs" placeholder='["--port","3000"]'></label>
      <div class="modal-status" id="mcpAddStatus"></div>
      <div class="modal-actions"><button class="btn" onclick="closeModal()">Cancel</button><button class="btn btn-accent" id="btnDoAddMcp">Add</button></div>
    `);
    document.querySelectorAll('.install-target').forEach(btn => {
      btn.addEventListener('click', () => btn.classList.toggle('selected'));
    });
    document.getElementById('btnDoAddMcp').addEventListener('click', async () => {
      const sources = Array.from(document.querySelectorAll('.install-target.selected')).map(btn => btn.dataset.source);
      const name = $('#mcpName').value.trim();
      const url = $('#mcpUrl').value.trim();
      const command = $('#mcpCommand').value.trim();
      const status = $('#mcpAddStatus');
      if (!sources.length) { status.textContent = 'Select at least one target.'; status.className = 'modal-status error'; return; }
      if (!name) { status.textContent = 'Name is required.'; status.className = 'modal-status error'; return; }
      if (!url && !command) { status.textContent = 'URL or command is required.'; status.className = 'modal-status error'; return; }
      let args = [];
      try { args = $('#mcpArgs').value ? JSON.parse($('#mcpArgs').value) : []; } catch {
        status.textContent = 'Args must be valid JSON.';
        status.className = 'modal-status error';
        return;
      }
      const btn = document.getElementById('btnDoAddMcp');
      btn.disabled = true;
      status.textContent = 'Adding...';
      status.className = 'modal-status';
      try {
        for (const source of sources) {
          const result = await api('/mcp', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ source, name, url: url || undefined, command: command || undefined, args }),
          });
          if (result.error) throw new Error(`${source}: ${result.error}`);
        }
      } catch (err) {
        status.textContent = err.message || 'Add failed.';
        status.className = 'modal-status error';
        btn.disabled = false;
        return;
      }
      closeModal();
      renderMcp();
    });
  });
}

/* ── Settings View ── */
async function renderSettings() {
  const [claude, codex, plugins] = await Promise.all([api('/settings/claude'), api('/settings/codex'), api('/settings/plugins')]);
  $content().innerHTML = `
    <div class="split-layout">
      <div class="panel">
        <div class="panel-head"><div class="panel-title">Claude Code settings.json</div><button class="btn btn-accent" id="saveClaude">Save</button></div>
        <textarea class="config-editor" id="claudeEditor">${esc(JSON.stringify(claude, null, 2))}</textarea>
      </div>
      <div class="panel">
        <div class="panel-head"><div class="panel-title">Codex config.toml (JSON view)</div><button class="btn btn-accent" id="saveCodex">Save</button></div>
        <textarea class="config-editor" id="codexEditor">${esc(JSON.stringify(codex, null, 2))}</textarea>
      </div>
    </div>
    <div class="panel">
      <div class="panel-head"><div class="panel-title">Plugins</div></div>
      ${plugins.length === 0 ? '<div class="empty">No plugins</div>' : `<table class="tbl"><thead><tr><th>Source</th><th>Name</th><th>Version</th><th>Status</th></tr></thead><tbody>${plugins.map(p => `<tr><td>${sourceBadge(p.source)}</td><td>${esc(p.name)}</td><td>${esc(p.version || '-')}</td><td>${p.enabled ? '<span class="green">enabled</span>' : '<span class="muted">disabled</span>'}</td></tr>`).join('')}</tbody></table>`}
    </div>`;

  document.getElementById('saveClaude').addEventListener('click', async () => {
    try {
      await api('/settings/claude', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: $('#claudeEditor').value });
      alert('Claude settings saved');
    } catch { alert('Invalid JSON'); }
  });

  document.getElementById('saveCodex').addEventListener('click', async () => {
    try {
      await api('/settings/codex', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: $('#codexEditor').value });
      alert('Codex settings saved');
    } catch { alert('Invalid JSON'); }
  });
}

render();
