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
let sessionsAutoRefreshInFlight = false;
let sessionsLastSignature = '';
let sessionsSearchDebounceTimer = null;
let sessionsSearchRequestSeq = 0;
const SESSIONS_AUTO_REFRESH_MS = 3000;
const DASHBOARD_ACTIVITY_NAME = 'web-dashboard';
const DASHBOARD_ACTIVITY_TTL_MS = 10000;
const DASHBOARD_ACTIVITY_RENEW_MS = 5000;
let dashboardActivityTimer = null;

const $ = (sel) => document.querySelector(sel);
const $content = () => $('#content');
const $headerActions = () => $('#headerActions');
const $scanStatus = () => $('#scanStatus');

/* ── Nav ── */
$('#navTabs').addEventListener('click', (e) => {
  const btn = e.target.closest('.tbtn');
  if (!btn) return;
  switchTab(btn.dataset.tab);
});

function switchTab(tab) {
  currentTab = tab || 'tokmon';
  sessionsPage = 1;
  document.querySelectorAll('#navTabs .tbtn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === currentTab);
  });
  render();
}

function render() {
  if (currentTab !== 'tokmon') {
    destroyTokMon();
    clearHeaderActions();
  }
  const views = { tokmon: renderTokMon, sessions: renderSessions, skills: renderSkills, mcp: renderMcp, settings: renderSettings };
  const rendered = (views[currentTab] || views.tokmon)();
  Promise.resolve(rendered).then(() => containScrollWithinAll(document));
}

function renewDashboardActivity() {
  if (document.hidden) return;
  fetch('/api/activity', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: DASHBOARD_ACTIVITY_NAME, ttlMs: DASHBOARD_ACTIVITY_TTL_MS }),
  }).catch(() => {});
}

function releaseDashboardActivity() {
  fetch(`/api/activity/${encodeURIComponent(DASHBOARD_ACTIVITY_NAME)}`, { method: 'DELETE' }).catch(() => {});
}

function startDashboardActivity() {
  if (!dashboardActivityTimer) {
    dashboardActivityTimer = setInterval(renewDashboardActivity, DASHBOARD_ACTIVITY_RENEW_MS);
  }
  renewDashboardActivity();
}

function stopDashboardActivity() {
  if (dashboardActivityTimer) {
    clearInterval(dashboardActivityTimer);
    dashboardActivityTimer = null;
  }
  releaseDashboardActivity();
}

/* ── Helpers ── */
function esc(s) { if (!s) return ''; const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
function escAttr(s) { return esc(s).replace(/"/g, '&quot;').replace(/'/g, '&#39;'); }
function trunc(s, n) { return s && s.length > n ? s.slice(0, n) + '...' : s || ''; }
function filterSearchRows(listId, emptyId, query) {
  const list = document.getElementById(listId);
  if (!list) return { visibleCount: 0, activeVisible: false };
  const needle = (query || '').trim().toLowerCase();
  let visibleCount = 0;
  let activeVisible = false;
  list.querySelectorAll('.split-item[data-search]').forEach(row => {
    const matches = !needle || (row.dataset.search || '').includes(needle);
    row.hidden = !matches;
    if (matches) visibleCount += 1;
    if (matches && row.classList.contains('active')) activeVisible = true;
  });
  const empty = document.getElementById(emptyId);
  if (empty) empty.hidden = visibleCount > 0;
  return { visibleCount, activeVisible };
}
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

function sessionsQueryParams() {
  const f = sessionsFilters;
  const params = new URLSearchParams({ page: sessionsPage, limit: sessionsPageSize });
  if (f.source) params.set('source', f.source);
  if (f.q) params.set('q', f.q);
  params.set('archived', f.archived);
  return params;
}

function sessionsSignature(data) {
  const rows = data?.rows || [];
  return JSON.stringify({
    total: data?.total || 0,
    page: data?.page || sessionsPage,
    limit: data?.limit || sessionsPageSize,
    rows: rows.map(r => [r.id, r.last_active_at, r.message_count, r.is_active, r.archived, r.project_path, r.model, r.last_prompt]),
  });
}

function canAutoRefreshSessions() {
  if (currentTab !== 'sessions' || sessionsManageMode || document.hidden) return false;
  if ($('#modalOverlay')?.classList.contains('open')) return false;
  const active = document.activeElement;
  if (active?.closest?.('#content .filters input, #content .filters select')) return false;
  return true;
}

async function pollSessionsAutoRefresh() {
  if (!canAutoRefreshSessions() || sessionsAutoRefreshInFlight) return;
  sessionsAutoRefreshInFlight = true;
  const query = sessionsQueryParams().toString();
  try {
    await fetch('/api/scan', { method: 'POST' }).catch(() => null);
    const data = await api('/sessions?' + query);
    if (!canAutoRefreshSessions() || query !== sessionsQueryParams().toString()) return;
    const nextSignature = sessionsSignature(data);
    if (sessionsLastSignature && nextSignature !== sessionsLastSignature) {
      await renderSessions(data);
    } else {
      sessionsLastSignature = nextSignature;
    }
  } finally {
    sessionsAutoRefreshInFlight = false;
  }
}

setInterval(pollSessionsAutoRefresh, SESSIONS_AUTO_REFRESH_MS);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) stopDashboardActivity();
  else {
    startDashboardActivity();
    pollSessionsAutoRefresh();
  }
});
window.addEventListener('pagehide', stopDashboardActivity);
startDashboardActivity();

function renderScanStatus(status) {
  const el = $scanStatus();
  if (!el) return;
  const isIdle = !status?.running && !status?.error;
  const wasHidden = el.hidden;
  const oldHeight = wasHidden ? 0 : el.getBoundingClientRect().height;
  const oldTop = window.scrollY;
  const rebuildBtn = document.getElementById('btnRebuildDatabase');
  if (rebuildBtn) {
    rebuildBtn.disabled = !!status?.running;
    rebuildBtn.classList.toggle('is-running', !!status?.running);
  }
  if (isIdle) {
    el.hidden = true;
    el.classList.remove('idle', 'error');
    el.innerHTML = '';
    compensateScanStatusScroll(oldHeight, oldTop);
    return;
  }
  const percent = status.total ? Math.round((status.current / status.total) * 100) : 0;
  el.hidden = false;
  el.classList.toggle('idle', isIdle);
  el.classList.toggle('error', !!status.error);
  el.innerHTML = `
    <div class="scan-status-main">
      <span class="scan-dot"></span>
      <span>${status.error ? 'Scan failed' : isIdle ? 'Local index ready' : 'Scanning local data'}</span>
      <span class="scan-phase">${esc(status.error || status.phase || '')}</span>
    </div>
    <div class="scan-status-meta">
      <span>${status.current || 0}/${status.total || 0}</span>
      <span>${status.processed || 0} processed</span>
    </div>
    <div class="scan-progress" style="--scan-progress:${percent}%"><span></span></div>
  `;
  compensateScanStatusScroll(oldHeight, oldTop);
}

function compensateScanStatusScroll(oldHeight, oldTop) {
  const el = $scanStatus();
  if (!el || oldTop <= 0) return;
  const newHeight = el.hidden ? 0 : el.getBoundingClientRect().height;
  const delta = newHeight - oldHeight;
  if (delta) window.scrollBy(0, delta);
}

async function refreshScanStatus() {
  try {
    renderScanStatus(await api('/scan-status'));
  } catch {
    renderScanStatus(null);
  }
}

refreshScanStatus();
setInterval(refreshScanStatus, 1000);

async function rebuildDatabase() {
  openModal(`
    <div class="modal-fixed confirm-modal">
      <h3>Rebuild Database</h3>
      <div class="modal-note">
        This clears AgentMon's local index database and rescans Claude/Codex files. Original session, skill, MCP, and configuration files are not deleted.
      </div>
      <div class="modal-status" id="rebuildStatus"></div>
      <div class="modal-actions">
        <button class="btn" id="btnCancelRebuild">Cancel</button>
        <button class="btn btn-accent" id="btnConfirmRebuild">Rebuild</button>
      </div>
    </div>
  `);
  document.getElementById('btnCancelRebuild')?.addEventListener('click', closeModal);
  document.getElementById('btnConfirmRebuild')?.addEventListener('click', async () => {
    const btn = document.getElementById('btnConfirmRebuild');
    const status = document.getElementById('rebuildStatus');
    btn.disabled = true;
    status.textContent = 'Starting rebuild...';
    status.className = 'modal-status';
    try {
      const res = await fetch('/api/rebuild-database', { method: 'POST' });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || 'Failed to start rebuild.');
      closeModal();
      refreshScanStatus();
    } catch (err) {
      status.textContent = err.message || 'Failed to start rebuild.';
      status.className = 'modal-status error';
      btn.disabled = false;
    }
  });
}

document.getElementById('btnRebuildDatabase')?.addEventListener('click', rebuildDatabase);

function openModal(html) {
  $('#modal').innerHTML = html;
  $('#modalOverlay').classList.add('open');
  containScrollWithinAll($('#modalOverlay'));
}
function closeModal() { $('#modalOverlay').classList.remove('open'); }
$('#modalOverlay').addEventListener('click', (e) => { if (e.target === $('#modalOverlay')) closeModal(); });
function showNotice(title, message, variant = '') {
  openModal(`
    <div class="modal-fixed confirm-modal">
      <h3>${esc(title)}</h3>
      <div class="modal-note ${variant ? esc(variant) : ''}">${esc(message)}</div>
      <div class="modal-actions">
        <button class="btn btn-accent" id="btnNoticeOk">OK</button>
      </div>
    </div>
  `);
  document.getElementById('btnNoticeOk')?.addEventListener('click', closeModal);
}
function confirmAction({ title, message, confirmLabel = 'Confirm', danger = false, onConfirm }) {
  openModal(`
    <div class="modal-fixed confirm-modal">
      <h3>${esc(title)}</h3>
      <div class="modal-note">${esc(message)}</div>
      <div class="modal-status" id="confirmActionStatus"></div>
      <div class="modal-actions">
        <button class="btn" id="btnConfirmCancel">Cancel</button>
        <button class="btn ${danger ? 'btn-danger' : 'btn-accent'}" id="btnConfirmOk">${esc(confirmLabel)}</button>
      </div>
    </div>
  `);
  document.getElementById('btnConfirmCancel')?.addEventListener('click', closeModal);
  document.getElementById('btnConfirmOk')?.addEventListener('click', async () => {
    const btn = document.getElementById('btnConfirmOk');
    const status = document.getElementById('confirmActionStatus');
    btn.disabled = true;
    try {
      await onConfirm?.(status);
      closeModal();
    } catch (err) {
      status.textContent = err.message || 'Operation failed.';
      status.className = 'modal-status error';
      btn.disabled = false;
    }
  });
}
const VERTICAL_SCROLL_LOCK_SELECTOR = [
  '.scroll-contained',
  '.tokens-control-menu',
  '.pricing-modal',
  '.pricing-dialog',
  '.pricing-left',
  '.pricing-config-list',
  '.source-content',
  '.split-list',
  '.skill-md',
  '.config-editor',
  '.modal-overlay',
  '.modal',
  '.dir-picker-list',
  '.msg-list',
  '.token-session-popover',
  '.token-session-preview',
].join(', ');
const HORIZONTAL_SCROLL_LOCK_SELECTOR = [
  '.records-table-wrap',
  '.breakdown-table',
  '.heatmap-wrap',
].join(', ');
const INTERNAL_SCROLL_LOCK_SELECTOR = [
  VERTICAL_SCROLL_LOCK_SELECTOR,
  HORIZONTAL_SCROLL_LOCK_SELECTOR,
].join(', ');

function isScrollableOnAxis(el, axis) {
  return axis === 'y'
    ? el.scrollHeight > el.clientHeight + 1
    : el.scrollWidth > el.clientWidth + 1;
}

function isScrollBoundary(el, axis, delta) {
  if (!delta) return false;
  const scrollPos = axis === 'y' ? el.scrollTop : el.scrollLeft;
  const clientSize = axis === 'y' ? el.clientHeight : el.clientWidth;
  const scrollSize = axis === 'y' ? el.scrollHeight : el.scrollWidth;
  if (delta < 0) return scrollPos <= 0;
  return scrollPos + clientSize >= scrollSize - 1;
}

function handleContainedScroll(e, el) {
  if (!el) return;
  const deltaX = e.deltaX || 0;
  const deltaY = e.deltaY || 0;
  if (!deltaX && !deltaY) return;

  const axes = [];
  const locksVertical = el.matches?.(VERTICAL_SCROLL_LOCK_SELECTOR);
  const locksHorizontal = el.matches?.(HORIZONTAL_SCROLL_LOCK_SELECTOR);
  const canScrollY = isScrollableOnAxis(el, 'y');
  const canScrollX = isScrollableOnAxis(el, 'x');

  if (deltaY && (locksVertical || canScrollY)) {
    axes.push({ axis: 'y', delta: deltaY, canScroll: canScrollY });
  }
  if (deltaX && (locksHorizontal || canScrollX)) {
    axes.push({ axis: 'x', delta: deltaX, canScroll: canScrollX });
  }
  if (!axes.length) return;

  e.stopPropagation();
  const canMoveInside = axes.some(({ axis, delta, canScroll }) => (
    canScroll && !isScrollBoundary(el, axis, delta)
  ));
  if (!canMoveInside) e.preventDefault();
}

function containScrollWithin(el) {
  if (!el) return;
  el.classList.add('scroll-contained');
}

function containScrollWithinAll(root = document) {
  const nodes = [];
  if (root?.matches?.(VERTICAL_SCROLL_LOCK_SELECTOR)) nodes.push(root);
  root?.querySelectorAll?.(VERTICAL_SCROLL_LOCK_SELECTOR).forEach(el => nodes.push(el));
  nodes.forEach(containScrollWithin);
}

document.addEventListener('wheel', (e) => {
  const el = e.target?.closest?.(INTERNAL_SCROLL_LOCK_SELECTOR);
  if (el) handleContainedScroll(e, el);
}, { passive: false, capture: true });

window.AgentMonContainScrollWithin = containScrollWithin;
window.AgentMonContainScrollWithinAll = containScrollWithinAll;

/* ── TokMon View ── */
function renderTokMon() {
  if (tokmonInstance && document.getElementById('tokmonView')) {
    tokmonInstance.activate?.();
    return;
  }
  renderTokensHeaderActions();
  destroyTokMon();
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
                  <th>Time</th><th>Source</th><th>Session</th><th>Model</th>
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
  tokmonInstance?.activate?.();
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
function sessionsBatchLabel() {
  return sessionsFilters.archived === '1' ? 'Restore Selected' : 'Archive Selected';
}

function sessionsManageInlineHtml(rows, selectedCount, batchLabel) {
  if (!sessionsManageMode) return '';
  return `
    <label class="manage-check-all"><input type="checkbox" id="checkAllSessions" ${rows.length > 0 && selectedCount === rows.length ? 'checked' : ''}> Select page</label>
    <span class="manage-count">${selectedSessionIds.size} selected</span>
    <button class="btn" id="btnMigrateProject" ${selectedSessionIds.size ? '' : 'disabled'}>Migrate Project</button>
    <button class="btn" id="btnBatchArchive" ${selectedSessionIds.size ? '' : 'disabled'}>${batchLabel}</button>
    <button class="btn btn-danger" id="btnBatchDelete" ${selectedSessionIds.size ? '' : 'disabled'}>Delete Selected</button>
    <button class="btn" id="btnClearSelection" ${selectedSessionIds.size ? '' : 'disabled'}>Clear</button>
  `;
}

function sessionsResultsHtml(rows, total, pages, selectedCount, batchLabel) {
  return `
    ${rows.length === 0 ? '<div class="empty">No sessions found</div>' : `
    <div class="table-scroll sessions-table-wrap">
      <table class="tbl sessions-table ${sessionsManageMode ? 'manage-mode' : ''}">
        <thead><tr>
          <th class="check-col"></th>
          <th>Source</th><th>Project</th><th class="prompt-th">${showLastPrompt ? 'Last Prompt' : 'First Prompt'} <button class="btn-switch-prompt" id="btnSwitchPrompt">${showLastPrompt ? '← first' : 'last →'}</button></th><th>Model</th><th>Msgs</th><th>Last Active</th><th>Status</th>
        </tr></thead>
        <tbody>${rows.map(r => `
          <tr data-id="${escAttr(r.id)}" class="${selectedSessionIds.has(r.id) ? 'row-selected' : ''}">
            <td class="check-col">${sessionsManageMode ? `<input type="checkbox" class="session-check" data-id="${escAttr(r.id)}" ${selectedSessionIds.has(r.id) ? 'checked' : ''}>` : ''}</td>
            <td>${sourceBadge(r.source)}</td>
            <td class="muted">${esc(trunc(r.project_path?.split('/').pop(), 20))}</td>
            <td class="prompt-cell">${esc(trunc(showLastPrompt ? (r.last_prompt || r.first_prompt) : r.first_prompt, 50))}</td>
            <td>${esc(r.model || '?')}</td>
            <td>${r.message_count}</td>
            <td class="muted">${relTime(r.last_active_at)}</td>
            <td>${r.is_active ? '<span class="badge badge-active">Live</span>' : ''}${r.archived ? '<span class="badge badge-archived">Archived</span>' : ''}</td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>`}
    ${pages > 1 ? `<div class="pager">${Array.from({length: pages}, (_, i) => `<button class="${i + 1 === sessionsPage ? 'active' : ''}" data-page="${i + 1}">${i + 1}</button>`).join('')}</div>` : ''}
    <div class="pager"><span class="pager-info">${total} total</span><select id="fPageSize">${[10,15,25,50].map(n => `<option value="${n}" ${n === sessionsPageSize ? 'selected' : ''}>${n} / page</option>`).join('')}</select></div>
  `;
}

function bindSessionsResultsEvents(rows) {
  document.getElementById('fPageSize')?.addEventListener('change', (e) => {
    sessionsPageSize = parseInt(e.target.value, 10);
    sessionsPage = 1;
    renderSessions();
  });

  document.getElementById('btnSwitchPrompt')?.addEventListener('click', () => {
    showLastPrompt = !showLastPrompt;
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
}

function bindSessionsManageEvents(rows) {
  document.getElementById('btnClearSelection')?.addEventListener('click', () => {
    selectedSessionIds.clear();
    renderSessions();
  });

  document.getElementById('btnBatchArchive')?.addEventListener('click', async () => {
    const archived = sessionsFilters.archived === '1' ? 0 : 1;
    for (const id of selectedSessionIds) {
      await api('/sessions/' + id, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ archived }) });
    }
    selectedSessionIds.clear();
    renderSessions();
  });

  document.getElementById('btnBatchDelete')?.addEventListener('click', async () => {
    if (!selectedSessionIds.size) return;
    confirmAction({
      title: 'Delete Sessions',
      message: `Permanently delete ${selectedSessionIds.size} session(s) and their files? This cannot be undone.`,
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: async () => {
        for (const id of selectedSessionIds) {
          await api('/sessions/' + id, { method: 'DELETE' });
        }
        selectedSessionIds.clear();
        renderSessions();
      },
    });
  });

  document.getElementById('btnMigrateProject')?.addEventListener('click', () => {
    if (!selectedSessionIds.size) return;
    openMigrateProjectModal(rows.filter(r => selectedSessionIds.has(r.id)));
  });
}

async function updateSessionsSearchResults() {
  const requestSeq = ++sessionsSearchRequestSeq;
  await fetch('/api/scan', { method: 'POST' }).catch(() => null);
  const data = await api('/sessions?' + sessionsQueryParams());
  if (currentTab !== 'sessions' || requestSeq !== sessionsSearchRequestSeq) return;
  sessionsLastSignature = sessionsSignature(data);
  const rows = data.rows || [];
  const total = data.total || 0;
  const pages = Math.ceil(total / sessionsPageSize);
  const selectedCount = rows.filter(r => selectedSessionIds.has(r.id)).length;
  const batchLabel = sessionsBatchLabel();
  const results = document.getElementById('sessionsResults');
  if (!results) return;
  results.innerHTML = sessionsResultsHtml(rows, total, pages, selectedCount, batchLabel);
  const manageInline = document.getElementById('sessionsManageInline');
  if (manageInline) manageInline.innerHTML = sessionsManageInlineHtml(rows, selectedCount, batchLabel);
  bindSessionsResultsEvents(rows);
  bindSessionsManageEvents(rows);
  containScrollWithinAll(results);
}

async function renderSessions(prefetchedData = null) {
  renderSessionsHeaderActions();
  const f = sessionsFilters;
  if (!prefetchedData) await fetch('/api/scan', { method: 'POST' }).catch(() => null);
  const data = prefetchedData || await api('/sessions?' + sessionsQueryParams());
  if (currentTab !== 'sessions') return;
  sessionsLastSignature = sessionsSignature(data);
  const rows = data.rows || [];
  const total = data.total || 0;
  const pages = Math.ceil(total / sessionsPageSize);
  const selectedCount = rows.filter(r => selectedSessionIds.has(r.id)).length;
  const batchLabel = sessionsBatchLabel();

  $content().innerHTML = `
    <div class="filters">
      <select id="fSource"><option value="">All Sources</option><option value="claude-code">Claude Code</option><option value="codex">Codex</option></select>
      <input id="fSearch" placeholder="Search project, model, prompt..." value="${esc(f.q)}">
      <button class="btn ${sessionsManageMode ? 'btn-accent' : ''}" id="btnManageSessions">${sessionsManageMode ? 'Exit Manage' : 'Manage'}</button>
      ${sessionsManageMode ? `
        <div class="manage-inline" id="sessionsManageInline">${sessionsManageInlineHtml(rows, selectedCount, batchLabel)}</div>
      ` : ''}
    </div>
    <div class="panel" id="sessionsResults">${sessionsResultsHtml(rows, total, pages, selectedCount, batchLabel)}</div>`;

  $('#fSource').value = f.source;

  for (const id of ['fSource', 'fSearch']) {
    const el = document.getElementById(id);
    const updateFilters = () => {
      sessionsFilters = {
        source: $('#fSource').value, project: '', model: '',
        q: $('#fSearch').value, archived: sessionsFilters.archived,
      };
      sessionsPage = 1;
      selectedSessionIds.clear();
    };
    if (id === 'fSearch') {
      el.addEventListener('input', () => {
        updateFilters();
        clearTimeout(sessionsSearchDebounceTimer);
        sessionsSearchDebounceTimer = setTimeout(updateSessionsSearchResults, 180);
      });
    } else {
      el.addEventListener('change', () => {
        updateFilters();
        renderSessions();
      });
    }
  }

  document.getElementById('btnManageSessions')?.addEventListener('click', () => {
    sessionsManageMode = !sessionsManageMode;
    if (!sessionsManageMode) selectedSessionIds.clear();
    renderSessions();
  });

  bindSessionsResultsEvents(rows);
  bindSessionsManageEvents(rows);
}

function openMigrateProjectModal(selectedRows = []) {
  const count = selectedSessionIds.size;
  const liveCount = selectedRows.filter(r => r.is_active).length;
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
    ${liveCount ? `<div class="modal-note warning">Selected sessions include ${liveCount} live session(s). Migration is allowed, but active tools may keep writing to the previous file until that session ends.</div>` : ''}
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
  containScrollWithin(listEl);
  root._agentMonDirPickerCleanup = cleanup;

  loadDir(currentPath);
}
window.AgentMonDirectoryPicker = initDirectoryPicker;

async function showSessionDetail(id) {
  const data = await api('/sessions/' + id + '?limit=99999');
  if (data.error) throw new Error(data.error || 'Session not found.');
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
  containScrollWithin(list);
  document.getElementById('msgScrollTop')?.addEventListener('click', () => { if (list) list.scrollTop = 0; });
  document.getElementById('msgScrollBottom')?.addEventListener('click', () => { if (list) list.scrollTop = list.scrollHeight; });
}

async function openSessionFromUsageLog(id, options = {}) {
  const sessionId = String(id || '').trim();
  if (!sessionId) return;

  let archived = '0';
  let source = options.source || '';
  try {
    const session = await api('/sessions/' + encodeURIComponent(sessionId) + '?limit=1');
    if (!session.error) {
      archived = session.archived ? '1' : '0';
      source = session.source || source;
    }
  } catch {}

  sessionsFilters = {
    source,
    project: '',
    model: '',
    q: sessionId,
    archived,
  };
  selectedSessionIds.clear();
  sessionsManageMode = false;
  switchTab('sessions');
  try {
    await showSessionDetail(sessionId);
  } catch (err) {
    showNotice('Session Not Found', err.message || 'This token record points to a session that is not indexed in Sessions.', 'error');
  }
}
window.AgentMonOpenSession = openSessionFromUsageLog;

/* ── Skills View ── */
let selectedSkillName = null;
async function renderSkills(options = {}) {
  const skills = Array.isArray(options.skills) ? options.skills : await api('/skills');

  const prevScroll = $content().querySelector('.split-list')?.scrollTop ?? 0;

  const skillsByName = {};
  const uniqueSkills = [];
  const seenKeys = new Set();
  const skillKey = (s) => (s.scope || 'user') === 'user'
    ? `user:${s.name}`
    : `${s.scope || 'user'}:${s.source}:${s.name}:${s.path}`;
  const peerSlot = (s) => (s.scope || 'user') === 'user'
    ? s.source
    : `${s.source}:${s.scope || 'user'}:${s.path}`;
  for (const s of skills) {
    const key = skillKey(s);
    const slot = peerSlot(s);
    if (!skillsByName[key]) skillsByName[key] = {};
    skillsByName[key][slot] = s;
    if (!seenKeys.has(key)) {
      seenKeys.add(key);
      uniqueSkills.push({ ...s, _key: key });
    }
  }
  const skillQuery = skillsSearch.trim().toLowerCase();
  const skillMatchesSearch = (s) => {
    const peers = skillsByName[s._key] || {};
    const haystack = [s.name, s.description, s.path, s.symlink_target, ...Object.keys(peers)].filter(Boolean).join(' ').toLowerCase();
    return !skillQuery || haystack.includes(skillQuery);
  };
  const skillSearchText = (s) => {
    const peers = skillsByName[s._key] || {};
    return [s.name, s.description, s.path, s.symlink_target, ...Object.keys(peers)].filter(Boolean).join(' ').toLowerCase();
  };
  const visibleSkills = uniqueSkills.filter(skillMatchesSearch);

  if (selectedSkillName && !visibleSkills.some(s => s._key === selectedSkillName)) selectedSkillName = null;
  const peerMap = selectedSkillName ? (skillsByName[selectedSkillName] || {}) : {};
  const detail = peerMap['claude-code'] || peerMap['codex'] || Object.values(peerMap)[0] || null;
  const isBroken = detail && detail.description && detail.description.startsWith('Broken symlink');
  const isReadOnlySkill = detail && (detail.scope || 'user') !== 'user';
  const brokenCount = skills.filter(s => (s.description || '').startsWith('Broken symlink')).length;
  const ccInstalled = !!peerMap['claude-code'];
  const codexInstalled = !!peerMap['codex'];
  const realTarget = detail ? (detail.symlink_target || detail.path) : '';
  const manageableVisibleSkills = visibleSkills.filter(s => Object.values(skillsByName[s._key] || {}).some(peer => (peer.scope || 'user') === 'user'));
  const selectedSkillCount = manageableVisibleSkills.filter(s => selectedSkillNames.has(s._key)).length;

  function platformPillsHtml() {
    if (!detail || isBroken || isReadOnlySkill) return '';
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
          <label class="manage-check-all"><input type="checkbox" id="checkAllSkills" ${manageableVisibleSkills.length > 0 && selectedSkillCount === manageableVisibleSkills.length ? 'checked' : ''}> Select all</label>
          <span class="manage-count">${selectedSkillNames.size} selected</span>
          <button class="btn btn-danger" id="btnBatchDeleteSkills" ${selectedSkillNames.size ? '' : 'disabled'}>Uninstall Selected</button>
          <button class="btn" id="btnClearSkillSelection" ${selectedSkillNames.size ? '' : 'disabled'}>Clear</button>
        </div>
      ` : ''}
    </div>
    <div class="split-layout">
      <div class="panel split-list" id="skillList"><div class="empty" id="skillSearchEmpty" ${visibleSkills.length === 0 ? '' : 'hidden'}>No skills</div>${uniqueSkills.map(s => {
        const broken = s.description && s.description.startsWith('Broken symlink');
        const peers = skillsByName[s._key] || {};
        const platforms = Array.from(new Set(Object.values(peers).map(peer => peer.source)));
        const manageable = Object.values(peers).some(peer => (peer.scope || 'user') === 'user');
        const scopes = Array.from(new Set(Object.values(peers).map(peer => peer.scope || 'user')));
        const scopeLabel = scopes.includes('user') ? (scopes.length > 1 ? scopes.join('/') : 'user') : scopes.join('/');
        return `
        <div class="split-item ${skillsManageMode ? 'with-check' : ''} ${s._key === selectedSkillName ? 'active' : ''} ${selectedSkillNames.has(s._key) ? 'row-selected' : ''}" data-key="${escAttr(s._key)}" data-search="${escAttr(skillSearchText(s))}" ${skillMatchesSearch(s) ? '' : 'hidden'}>
          ${skillsManageMode && manageable ? `<input type="checkbox" class="split-check skill-check" data-key="${escAttr(s._key)}" ${selectedSkillNames.has(s._key) ? 'checked' : ''}>` : ''}
          <div class="split-item-body">
            <div class="split-item-name">${platforms.map(p => sourceBadge(p)).join(' ')} ${esc(s.name)}</div>
            <div class="split-item-meta">${broken ? '<span class="red">broken</span>' : s.enabled ? '<span class="green">enabled</span>' : '<span class="muted">disabled</span>'} · ${esc(scopeLabel)} · ${esc(s.is_symlink ? 'symlink' : 'local')}</div>
          </div>
        </div>`;
      }).join('')}
      </div>
      <div class="panel" id="skillDetail">${!detail ? '<div class="empty">Select a skill</div>' : `
        <div class="detail-header">
          <div class="detail-title">${esc(detail.name)}</div>
          <div class="detail-actions">
            ${isBroken || isReadOnlySkill ? '' : `<label class="toggle"><input type="checkbox" id="toggleSkill" ${detail.enabled ? 'checked' : ''}><span class="toggle-slider"></span></label>`}
          </div>
        </div>
        <div style="font-family:var(--font-mono);font-size:0.72rem;color:var(--text-muted);margin-bottom:8px;">
          ${esc(detail.scope || 'user')} · ${esc(detail.is_symlink ? 'symlink' : 'local')} · ${esc(detail.path)}
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
    const result = filterSearchRows('skillList', 'skillSearchEmpty', skillsSearch);
    if (!result.activeVisible) {
      selectedSkillName = null;
      document.getElementById('skillDetail').innerHTML = '<div class="empty">Select a skill</div>';
      document.querySelectorAll('#skillList .split-item.active').forEach(row => row.classList.remove('active'));
    }
  });

  document.getElementById('btnManageSkills')?.addEventListener('click', () => {
    skillsManageMode = !skillsManageMode;
    if (!skillsManageMode) selectedSkillNames.clear();
    renderSkills();
  });

  document.getElementById('checkAllSkills')?.addEventListener('change', (e) => {
    if (e.target.checked) manageableVisibleSkills.forEach(s => selectedSkillNames.add(s._key));
    else manageableVisibleSkills.forEach(s => selectedSkillNames.delete(s._key));
    renderSkills();
  });

  document.getElementById('btnClearSkillSelection')?.addEventListener('click', () => {
    selectedSkillNames.clear();
    renderSkills();
  });

  document.getElementById('btnBatchDeleteSkills')?.addEventListener('click', async () => {
    if (!selectedSkillNames.size) return;
    confirmAction({
      title: 'Uninstall Skills',
      message: `Uninstall ${selectedSkillNames.size} selected skill(s) from all user-installed platforms? System, plugin, and curated skills are read-only and will be left untouched.`,
      confirmLabel: 'Uninstall',
      danger: true,
      onConfirm: async () => {
        for (const key of selectedSkillNames) {
          const peers = skillsByName[key] || {};
          for (const peer of Object.values(peers)) {
            if ((peer.scope || 'user') !== 'user') continue;
            await api('/skills/' + encodeURIComponent(peer.id), { method: 'DELETE' });
          }
        }
        selectedSkillNames.clear();
        selectedSkillName = null;
        renderSkills();
      },
    });
  });

  $content().querySelectorAll('.platform-pill').forEach(pill => {
    pill.addEventListener('click', async () => {
      const platform = pill.dataset.platform;
      const isInstalled = pill.classList.contains('installed');
      const bothInstalled = ccInstalled && codexInstalled;
      if (isInstalled) {
        if (!bothInstalled) { showNotice('Skill Required', 'At least one platform must have this skill installed.'); return; }
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
      const key = el.dataset.key;
      if (skillsManageMode) {
        if (e.target.closest('input')) return;
        const peers = skillsByName[key] || {};
        const manageable = Object.values(peers).some(peer => (peer.scope || 'user') === 'user');
        if (!manageable) return;
        if (selectedSkillNames.has(key)) selectedSkillNames.delete(key);
        else selectedSkillNames.add(key);
        renderSkills();
        return;
      }
      selectedSkillName = key;
      renderSkills();
    });
  });

  $content().querySelectorAll('.skill-check').forEach(input => {
    input.addEventListener('change', () => {
      const key = input.dataset.key;
      if (input.checked) selectedSkillNames.add(key);
      else selectedSkillNames.delete(key);
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
    confirmAction({
      title: 'Clean Broken Skills',
      message: `Remove ${brokenCount} broken symlink skill(s)? This only removes broken links from the local skills directory.`,
      confirmLabel: 'Clean',
      danger: true,
      onConfirm: async () => {
        await api('/skills/cleanup-broken', { method: 'POST' });
        selectedSkillName = null;
        renderSkills();
      },
    });
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
async function renderMcp(options = {}) {
  const items = Array.isArray(options.items) ? options.items : await api('/mcp');
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
  const mcpMatchesSearch = (m) => {
    const peers = mcpByName[m.name] || {};
    const peerValues = Object.values(peers).flatMap(peer => [peer.url, peer.command, peer.args, peer.config_raw]);
    const haystack = [m.name, m.url, m.command, m.args, m.config_raw, ...Object.keys(peers), ...peerValues].filter(Boolean).join(' ').toLowerCase();
    return !mcpQuery || haystack.includes(mcpQuery);
  };
  const mcpSearchText = (m) => {
    const peers = mcpByName[m.name] || {};
    const peerValues = Object.values(peers).flatMap(peer => [peer.url, peer.command, peer.args, peer.config_raw]);
    return [m.name, m.url, m.command, m.args, m.config_raw, ...Object.keys(peers), ...peerValues].filter(Boolean).join(' ').toLowerCase();
  };
  const visibleMcp = uniqueMcp.filter(mcpMatchesSearch);

  if (selectedMcpName && !visibleMcp.some(m => m.name === selectedMcpName)) selectedMcpName = null;
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
      <div class="panel split-list" id="mcpList"><div class="empty" id="mcpSearchEmpty" ${visibleMcp.length === 0 ? '' : 'hidden'}>No MCP servers</div>${uniqueMcp.map(m => {
        const mcpPeers = mcpByName[m.name] || {};
        const mcpPlatforms = Object.keys(mcpPeers);
        return `
        <div class="split-item ${mcpManageMode ? 'with-check' : ''} ${m.name === selectedMcpName ? 'active' : ''} ${selectedMcpNames.has(m.name) ? 'row-selected' : ''}" data-name="${escAttr(m.name)}" data-search="${escAttr(mcpSearchText(m))}" ${mcpMatchesSearch(m) ? '' : 'hidden'}>
          ${mcpManageMode ? `<input type="checkbox" class="split-check mcp-check" data-name="${escAttr(m.name)}" ${selectedMcpNames.has(m.name) ? 'checked' : ''}>` : ''}
          <div class="split-item-body">
            <div class="split-item-name">${mcpPlatforms.map(p => sourceBadge(p)).join(' ')} ${esc(m.name)}</div>
            <div class="split-item-meta">${esc(m.url || m.command || '')}</div>
          </div>
        </div>`;
      }).join('')}
      </div>
      <div class="panel" id="mcpDetail">${!detail ? '<div class="empty">Select an MCP server</div>' : `
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
    const result = filterSearchRows('mcpList', 'mcpSearchEmpty', mcpSearch);
    if (!result.activeVisible) {
      selectedMcpName = null;
      document.getElementById('mcpDetail').innerHTML = '<div class="empty">Select an MCP server</div>';
      document.querySelectorAll('#mcpList .split-item.active').forEach(row => row.classList.remove('active'));
    }
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
    confirmAction({
      title: 'Delete MCP Servers',
      message: `Delete ${selectedMcpNames.size} selected MCP server(s) from all installed platforms?`,
      confirmLabel: 'Delete',
      danger: true,
      onConfirm: async () => {
        for (const name of selectedMcpNames) {
          const peers = mcpByName[name] || {};
          for (const peer of Object.values(peers)) {
            await api('/mcp/' + encodeURIComponent(peer.id), { method: 'DELETE' });
          }
        }
        selectedMcpNames.clear();
        selectedMcpName = null;
        renderMcp();
      },
    });
  });

  $content().querySelectorAll('.platform-pill').forEach(pill => {
    pill.addEventListener('click', async () => {
      const platform = pill.dataset.platform;
      const isInstalled = pill.classList.contains('installed');
      const bothInstalled = mcpCcInstalled && mcpCodexInstalled;
      if (isInstalled) {
        if (!bothInstalled) { showNotice('MCP Required', 'At least one platform must have this MCP server.'); return; }
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
      showNotice('Settings Saved', 'Claude settings saved.');
    } catch { showNotice('Invalid JSON', 'Claude settings could not be saved because the JSON is invalid.', 'error'); }
  });

  document.getElementById('saveCodex').addEventListener('click', async () => {
    try {
      await api('/settings/codex', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: $('#codexEditor').value });
      showNotice('Settings Saved', 'Codex settings saved.');
    } catch { showNotice('Invalid JSON', 'Codex settings could not be saved because the JSON is invalid.', 'error'); }
  });
}

render();
