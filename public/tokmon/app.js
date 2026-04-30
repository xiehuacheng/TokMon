const $ = s => document.querySelector(s);
const C = { accent: '#58a6ff', green: '#3fb950', orange: '#d29922', pink: '#f778ba', purple: '#bc8cff', red: '#f85149', teal: '#2dd4bf' };

const today = new Date();
$('#dateTo').value = fmtDateTime(today);

function fmtDate(d) {
  const y = d.getFullYear(), m = String(d.getMonth()+1).padStart(2,'0'), dd = String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${dd}`;
}
function fmtDateTime(d) {
  return `${fmtDate(d)}T${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
}
function num(n) {
  if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return String(n);
}

const tt = { backgroundColor: '#161b22', borderColor: '#30363d',
  textStyle: { fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: '#e6edf3' } };
const ax = { color: '#484f58', fontSize: 10, fontFamily: "'JetBrains Mono', monospace" };
const sp = { lineStyle: { color: '#21262d', type: 'dashed' } };

const trendChart = echarts.init($('#trendChart'));
const pieChart = echarts.init($('#pieChart'));
let cachedHeatmap = null;
let resizeTimer;
function onResize() {
  trendChart.resize(); pieChart.resize();
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => { if (cachedHeatmap) renderHeatmap(cachedHeatmap); }, 100);
}
window.addEventListener('resize', onResize);

setTimeout(() => {
  const heatWrap = document.getElementById('heatmapWrap');
  if (heatWrap) {
    new ResizeObserver(() => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => { if (cachedHeatmap) renderHeatmap(cachedHeatmap); }, 100);
    }).observe(heatWrap.closest('.panel'));
  }
}, 0);

$('#btnGear').addEventListener('click', (e) => {
  e.stopPropagation();
  $('#btnGear').classList.toggle('open');
  $('#settingsMenu').classList.toggle('open');
});
document.addEventListener('click', (e) => {
  if (!e.target.closest('.settings-wrap')) {
    $('#btnGear').classList.remove('open');
    $('#settingsMenu').classList.remove('open');
  }
});

let currentInterval = 'day';
function setIntervalMode(mode) {
  currentInterval = mode;
  $('#btnHourly').classList.toggle('active', mode === 'hour');
  $('#btnDaily').classList.toggle('active', mode === 'day');
}
$('#btnHourly').addEventListener('click', (e) => {
  e.stopPropagation();
  setIntervalMode('hour');
  refresh();
});
$('#btnDaily').addEventListener('click', (e) => {
  e.stopPropagation();
  setIntervalMode('day');
  refresh();
});
setIntervalMode('day');

$('#source').addEventListener('change', refresh);
$('#dateFrom').addEventListener('change', () => { clearRangeBtn(); autoInterval(); refresh(); });
$('#dateTo').addEventListener('change', () => { setLiveMode(false); clearRangeBtn(); autoInterval(); refresh(); });

let liveMode = true;
let timeMode = 'exact';

function setLiveMode(on) {
  liveMode = on;
  $('#btnNow').classList.toggle('active', on);
  $('#btnNow').disabled = on;
}

$('#btnNow').addEventListener('click', () => {
  if (liveMode) return;
  setLiveMode(true);
  $('#dateTo').value = fmtDateTime(new Date());
  refresh();
});

$('#btnExact').addEventListener('click', (e) => {
  e.stopPropagation();
  timeMode = 'exact';
  $('#btnExact').classList.add('active');
  $('#btnRound').classList.remove('active');
  reapplyRange();
});
$('#btnRound').addEventListener('click', (e) => {
  e.stopPropagation();
  timeMode = 'round';
  $('#btnRound').classList.add('active');
  $('#btnExact').classList.remove('active');
  reapplyRange();
});

setLiveMode(true);

let lastRangeBtn = null;

function reapplyRange() {
  if (lastRangeBtn) lastRangeBtn.dispatchEvent(new MouseEvent('click', { bubbles: false }));
}

document.querySelectorAll('.range-btns .rbtn[data-hours], .range-btns .rbtn[data-days]').forEach(btn => {
  btn.addEventListener('click', () => {
    lastRangeBtn = btn;
    const to = new Date();
    const from = new Date(to);
    if (btn.dataset.hours) {
      const hours = parseInt(btn.dataset.hours);
      if (timeMode === 'round') {
        from.setHours(to.getHours() - hours + 1, 0, 0, 0);
      } else {
        from.setHours(from.getHours() - hours);
      }
      setIntervalMode('hour');
    } else {
      const days = parseInt(btn.dataset.days);
      if (timeMode === 'round') {
        from.setDate(to.getDate() - days + 1);
        from.setHours(0, 0, 0, 0);
      } else {
        from.setDate(to.getDate() - days);
      }
      autoInterval(from, to);
    }
    $('#dateFrom').value = fmtDateTime(from);
    $('#dateTo').value = fmtDateTime(to);
    document.querySelectorAll('.range-btns .rbtn[data-hours], .range-btns .rbtn[data-days]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    setLiveMode(true);
    refresh();
  });
});

function clearRangeBtn() {
  document.querySelectorAll('.range-btns .rbtn[data-hours], .range-btns .rbtn[data-days]').forEach(b => b.classList.remove('active'));
  lastRangeBtn = null;
}

function toggleFilter(type, value) {
  if (!type || (activeFilter && activeFilter.type === type && activeFilter.value === value)) {
    activeFilter = null;
  } else {
    activeFilter = { type, value };
  }
  recordsPage = 0;
  refresh();
}

function autoInterval(from = new Date($('#dateFrom').value), to = new Date($('#dateTo').value)) {
  const diffMs = to - from;
  setIntervalMode(diffMs < 86400000 ? 'hour' : 'day');
}

let prevDigits = [];
let lastHeroValue = -1;
function rollToNumber(n, isCost) {
  if (n === lastHeroValue) return;
  lastHeroValue = n;

  const str = String(n);
  const padded = isCost ? str.padStart(Math.max(prevDigits.length, 3, str.length), '0') : str.padStart(Math.max(prevDigits.length, str.length), '0');
  const container = $('#heroDigits');
  const isCompact = (window.innerWidth >= 1200 && window.innerHeight <= 900) || window.innerWidth <= 1000;
  const isSmall = window.innerWidth <= 600;
  const CELL = isSmall ? 56 : isCompact ? 80 : 130;
  const NUMS = [8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1];

  const groups = [];
  if (isCost) {
    const chars = padded.split('');
    const dotPos = chars.length - 2;
    for (let i = 0; i < chars.length; i++) {
      if (i === dotPos) groups.push('.');
      groups.push(chars[i]);
    }
    groups.unshift('$');
  } else {
    let chars = padded.split('').reverse();
    for (let i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 === 0) groups.push(',');
      groups.push(chars[i]);
    }
    groups.reverse();
  }

  container.innerHTML = groups.map(ch => {
    if (ch === ',' || ch === '.' || ch === '$') return `<span class="hero-sep">${ch}</span>`;
    return `<div class="hero-digit"><div class="hero-digit-inner">${
      NUMS.map(d => `<div class="hero-digit-num">${d}</div>`).join('')
    }</div></div>`;
  }).join('');

  const digitEls = container.querySelectorAll('.hero-digit-inner');
  const digits = groups.filter(c => c !== ',' && c !== '.' && c !== '$');
  let di = 0;
  digits.forEach((d, i) => {
    const el = digitEls[di++];
    const target = parseInt(d);
    const prev = parseInt(prevDigits[i]) || 0;
    const targetIdx = target + 2;
    const prevIdx = prev + 2;
    const offset = -(targetIdx - 1) * CELL;
    const prevOffset = -(prevIdx - 1) * CELL;

    el.querySelectorAll('.hero-digit-num').forEach(n => n.classList.remove('active'));
    el.children[targetIdx].classList.add('active');

    if (prev !== target || prevDigits.length === 0) {
      const dist = Math.abs(target - prev);
      const duration = 0.8 + dist * 0.12 + i * 0.04;
      el.style.transition = 'none';
      el.style.transform = `translateY(${prevOffset}px)`;
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          el.style.transition = `transform ${duration}s cubic-bezier(0.23, 1, 0.32, 1)`;
          el.style.transform = `translateY(${offset}px)`;
        });
      });
    } else {
      el.style.transform = `translateY(${offset}px)`;
    }
  });

  prevDigits = digits;
}

let breakdownTab = 'model';
let cachedSummary = null;
const PAGE_SIZE = 10;
let currentPage = 0;
let activeFilter = null; // { type: 'model', value: 'xxx' } or { type: 'source', value: 'xxx' }

document.querySelectorAll('.tbtn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tbtn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    breakdownTab = btn.dataset.tab;
    currentPage = 0;
    renderBreakdown();
  });
});

let activeSeries = 'total';
let cachedTrend = null;
let cachedCompareTrend = null;
let cachedFrom = '', cachedTo = '', cachedInterval = 'day';
let cachedRawValues = {};
let cachedCompareRawValues = null;

function loadPricing() {
  try { return JSON.parse(localStorage.getItem('tokmon_pricing') || '{}'); } catch { return {}; }
}
function savePricing(p) { localStorage.setItem('tokmon_pricing', JSON.stringify(p)); }

function calcCost(byModel) {
  const pricing = loadPricing();
  let total = 0;
  for (const m of byModel) {
    const p = pricing[m.model];
    if (!p) continue;
    total += (m.input_tokens || 0) / 1e6 * (p.input || 0);
    total += (m.output_tokens || 0) / 1e6 * (p.output || 0);
    total += (m.cache_creation || 0) / 1e6 * (p.cache_create || 0);
    total += (m.cache_read || 0) / 1e6 * (p.cache_read || 0);
  }
  return total;
}

function fmtCost(n) {
  if (n >= 1000) return '$' + (n / 1000).toFixed(1) + 'K';
  if (n >= 1) return '$' + n.toFixed(2);
  if (n >= 0.01) return '$' + n.toFixed(3);
  return '$' + n.toFixed(4);
}

$('#btnPricing').addEventListener('click', (e) => {
  e.stopPropagation();
  $('#btnGear').classList.remove('open');
  $('#settingsMenu').classList.remove('open');
  openPricingModal();
});
$('#pricingClose').addEventListener('click', () => { closePricingModal(); });
$('#pricingModal').addEventListener('click', (e) => { if (e.target === $('#pricingModal')) closePricingModal(); });

function closePricingModal() {
  $('#pricingModal').classList.remove('open');
  document.body.style.overflow = '';
}

$('#btnSources').addEventListener('click', (e) => {
  e.stopPropagation();
  $('#btnGear').classList.remove('open');
  $('#settingsMenu').classList.remove('open');
  openSourcesModal();
});
$('#sourcesClose').addEventListener('click', () => { closeSourcesModal(); });
$('#sourcesCancel').addEventListener('click', () => { closeSourcesModal(); });
$('#sourcesModal').addEventListener('click', (e) => { if (e.target === $('#sourcesModal')) closeSourcesModal(); });

function closeSourcesModal() {
  $('#sourcesModal').classList.remove('open');
  $('#sourcesStatus').textContent = '';
  $('#sourcesStatus').className = 'source-status';
  document.body.style.overflow = '';
}

function setSourceStatus(text, type = '') {
  const el = $('#sourcesStatus');
  el.textContent = text;
  el.className = `source-status ${type}`.trim();
}

async function openSourcesModal() {
  setSourceStatus('Loading source configuration...');
  $('#sourcesModal').classList.add('open');
  document.body.style.overflow = 'hidden';

  try {
    const config = await fetch('/api/tokmon/config').then(r => {
      if (!r.ok) throw new Error('Failed to load source configuration');
      return r.json();
    });
    const claude = config.sources?.['claude-code'] || {};
    const codex = config.sources?.codex || {};
    $('#claudePath').value = claude.path || '~/.claude/projects';
    $('#codexPath').value = codex.path || '~/.codex/sessions';
    $('#claudeResolved').textContent = claude.resolvedPath ? `Resolved: ${claude.resolvedPath}` : '';
    $('#codexResolved').textContent = codex.resolvedPath ? `Resolved: ${codex.resolvedPath}` : '';
    setSourceStatus('');
  } catch (err) {
    setSourceStatus(err.message || 'Failed to load source configuration', 'error');
  }
}

$('#sourcesSave').addEventListener('click', async () => {
  const claudePath = $('#claudePath').value.trim();
  const codexPath = $('#codexPath').value.trim();
  if (!claudePath || !codexPath) {
    setSourceStatus('Both log paths are required.', 'error');
    return;
  }

  setSourceStatus('Saving and scanning...');
  $('#sourcesSave').disabled = true;
  try {
    const res = await fetch('/api/tokmon/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sources: {
          'claude-code': { path: claudePath },
          codex: { path: codexPath },
        },
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Failed to save source configuration');

    $('#claudeResolved').textContent = `Resolved: ${data.sources['claude-code'].resolvedPath}`;
    $('#codexResolved').textContent = `Resolved: ${data.sources.codex.resolvedPath}`;
    setSourceStatus(`Saved. Imported ${data.inserted || 0} new records.`, 'success');
    refresh();
  } catch (err) {
    setSourceStatus(err.message || 'Failed to save source configuration', 'error');
  } finally {
    $('#sourcesSave').disabled = false;
  }
});

let allModels = [];
let pricingDraft = {};

async function openPricingModal() {
  const models = await fetch('/api/tokmon/models').then(r => r.json());
  allModels = models.map(m => m.model);
  pricingDraft = loadPricing();
  renderPricingLeft();
  renderPricingRight();
  $('#pricingModal').classList.add('open');
  document.body.style.overflow = 'hidden';
}

function renderPricingLeft() {
  const configured = Object.keys(pricingDraft);
  $('#pricingModelList').innerHTML = allModels.map(m => {
    const added = configured.includes(m);
    return `<div class="pricing-model-item${added ? ' added' : ''}" data-model="${m}">
      <span>${m}</span><span class="add-icon">+</span>
    </div>`;
  }).join('') || '<div class="pricing-empty">No models found</div>';

  document.querySelectorAll('.pricing-model-item').forEach(el => {
    el.addEventListener('click', () => {
      const model = el.dataset.model;
      if (pricingDraft[model]) return;
      pricingDraft[model] = { input: 0, output: 0, cache_create: 0, cache_read: 0 };
      renderPricingLeft();
      renderPricingRight();
    });
  });
}

function renderPricingRight() {
  const keys = Object.keys(pricingDraft);
  if (!keys.length) {
    $('#pricingConfigList').innerHTML = '<div class="pricing-empty">Click a model on the left to add pricing</div>';
    return;
  }
  $('#pricingConfigList').innerHTML = keys.map(m => {
    const p = pricingDraft[m];
    return `<div class="pricing-row" data-model="${m}">
      <div class="pricing-row-head">
        <span class="pricing-model-name">${m}</span>
        <button class="pricing-remove" data-model="${m}">Remove</button>
      </div>
      <div class="pricing-fields">
        <label>Input<input data-field="input" type="number" step="0.01" value="${p.input || ''}"></label>
        <label>Output<input data-field="output" type="number" step="0.01" value="${p.output || ''}"></label>
        <label>Cache W<input data-field="cache_create" type="number" step="0.01" value="${p.cache_create || ''}"></label>
        <label>Cache R<input data-field="cache_read" type="number" step="0.01" value="${p.cache_read || ''}"></label>
      </div>
    </div>`;
  }).join('');

  document.querySelectorAll('.pricing-remove').forEach(btn => {
    btn.addEventListener('click', () => {
      delete pricingDraft[btn.dataset.model];
      renderPricingLeft();
      renderPricingRight();
    });
  });
}

$('#pricingSave').addEventListener('click', () => {
  document.querySelectorAll('#pricingConfigList .pricing-row').forEach(row => {
    const model = row.dataset.model;
    pricingDraft[model] = {
      input: parseFloat(row.querySelector('[data-field=input]').value) || 0,
      output: parseFloat(row.querySelector('[data-field=output]').value) || 0,
      cache_create: parseFloat(row.querySelector('[data-field=cache_create]').value) || 0,
      cache_read: parseFloat(row.querySelector('[data-field=cache_read]').value) || 0,
    };
  });
  savePricing(pricingDraft);
  closePricingModal();
  refresh();
});

function calcAvgRates(byModel) {
  const pricing = loadPricing();
  let totalIn = 0, totalOut = 0, totalCc = 0, totalCr = 0;
  let costIn = 0, costOut = 0, costCc = 0, costCr = 0;
  for (const m of byModel) {
    const p = pricing[m.model];
    if (!p) continue;
    totalIn += m.input_tokens || 0;
    totalOut += m.output_tokens || 0;
    totalCc += m.cache_creation || 0;
    totalCr += m.cache_read || 0;
    costIn += (m.input_tokens || 0) / 1e6 * (p.input || 0);
    costOut += (m.output_tokens || 0) / 1e6 * (p.output || 0);
    costCc += (m.cache_creation || 0) / 1e6 * (p.cache_create || 0);
    costCr += (m.cache_read || 0) / 1e6 * (p.cache_read || 0);
  }
  return {
    input: totalIn ? costIn / totalIn * 1e6 : 0,
    output: totalOut ? costOut / totalOut * 1e6 : 0,
    cache_create: totalCc ? costCc / totalCc * 1e6 : 0,
    cache_read: totalCr ? costCr / totalCr * 1e6 : 0,
  };
}

function bucketCost(r, rates) {
  return (r[1] || 0) / 1e6 * rates.input
       + (r[2] || 0) / 1e6 * rates.output
       + (r[3] || 0) / 1e6 * rates.cache_create
       + (r[5] || 0) / 1e6 * rates.cache_read;
}

let cachedAvgRates = { input: 0, output: 0, cache_create: 0, cache_read: 0 };

const SERIES_DEF = {
  total:  { label: 'Total Tokens', icon: '∑', cls: 'accent', color: C.accent, field: r => r[1] + r[2] },
  reqs:   { label: 'Requests', icon: '⚡', cls: 'green', color: C.green, field: r => r[4] },
  input:  { label: 'Input Tokens', icon: '→', cls: 'purple', color: C.purple, field: r => r[1] },
  output: { label: 'Output Tokens', icon: '←', cls: 'pink', color: C.pink, field: r => r[2] },
  cache:  { label: 'Cache Created', icon: '◆', cls: 'orange', color: C.orange, field: r => r[3] },
  cacheHit: { label: 'Cache Hit', icon: '✦', cls: 'red', color: C.red, field: r => r[5] },
  cost:   { label: 'Est. Cost', icon: '$', cls: 'teal', color: C.teal, field: r => bucketCost(r, cachedAvgRates) },
};

function updateHero(forceReset) {
  const def = SERIES_DEF[activeSeries];
  const source = cachedCompareRawValues || cachedRawValues;
  const val = source[activeSeries] || 0;
  $('.hero-label').textContent = def.label.toUpperCase();
  const wrap = $('#heroDigits');
  wrap.style.setProperty('--hero-color', def.color);
  wrap.style.setProperty('--hero-glow', def.color + '66');
  wrap.style.setProperty('--hero-glow2', def.color + '26');
  if (activeSeries === 'cost') {
    const cents = Math.round(val * 100);
    if (forceReset) { lastHeroValue = -1; prevDigits = []; }
    rollToNumber(cents, true);
  } else {
    if (forceReset) { lastHeroValue = -1; prevDigits = []; }
    rollToNumber(val, false);
  }
}

function selectSeries(key) {
  activeSeries = key;
  document.querySelectorAll('.card').forEach((el, i) => {
    const keys = Object.keys(SERIES_DEF);
    el.classList.toggle('active', keys[i] === key);
  });
  updateHero(true);
  renderTrend();
  renderBreakdown();
  if (cachedHeatmap) renderHeatmap(cachedHeatmap);
}

function renderTrend() {
  if (!cachedTrend) return;
  const def = SERIES_DEF[activeSeries];
  const data = cachedTrend.map(r => [r[0], def.field(r)]);
  const compareData = cachedCompareTrend ? cachedCompareTrend.map(r => [r[0], def.field(r)]) : null;
  const useBar = data.length <= 3;

  const series = [];
  if (useBar) {
    series.push({
      type: 'bar', data,
      barMaxWidth: 40,
      itemStyle: { color: activeFilter ? '#6e7681' : def.color, borderRadius: [4, 4, 0, 0] },
      emphasis: { itemStyle: { color: activeFilter ? '#8b949e' : def.color } },
    });
    if (compareData) {
      series.push({
        type: 'bar', data: compareData,
        barMaxWidth: 28,
        itemStyle: { color: def.color, borderRadius: [4, 4, 0, 0] },
        emphasis: { itemStyle: { color: def.color } },
      });
    }
  } else {
    series.push({
      type: 'line', smooth: true, symbol: 'circle', symbolSize: 1, showSymbol: false,
      lineStyle: { width: 2, color: activeFilter ? '#6e7681' : def.color },
      areaStyle: { color: activeFilter ? '#6e7681' : def.color, opacity: 0.08 },
      itemStyle: { color: activeFilter ? '#6e7681' : def.color },
      emphasis: { itemStyle: { borderWidth: 2, borderColor: '#e6edf3' } },
      data,
    });
    if (compareData) {
      series.push({
        type: 'line', smooth: true, symbol: 'circle', symbolSize: 1, showSymbol: false,
        lineStyle: { width: 2, color: def.color },
        areaStyle: { color: def.color, opacity: 0.08 },
        itemStyle: { color: def.color },
        emphasis: { itemStyle: { borderWidth: 2, borderColor: '#e6edf3' } },
        data: compareData,
      });
    }
  }

  const xAxis = useBar
    ? { type: 'category', data: data.map(d => d[0]), axisLine: { lineStyle: { color: '#21262d' } }, axisLabel: ax, splitLine: { show: false } }
    : { type: 'time', min: cachedFrom, max: cachedTo, minInterval: cachedInterval === 'day' ? 86400000 : undefined,
        axisLine: { lineStyle: { color: '#21262d' } }, axisLabel: ax, splitLine: { show: false } };

  trendChart.setOption({
    backgroundColor: 'transparent',
    tooltip: { trigger: useBar ? 'item' : 'axis', confine: true, ...tt, axisPointer: useBar ? { type: 'none' } : { type: 'cross', crossStyle: { color: '#21262d' }, lineStyle: { color: '#30363d' } } },
    legend: { show: false },
    grid: { left: 10, right: 16, top: 16, bottom: 28, containLabel: true },
    xAxis,
    yAxis: { type: 'value', splitLine: sp, axisLabel: { ...ax, formatter: v => activeSeries === 'cost' ? fmtCost(v) : num(v) } },
    series,
  }, true);
}

function isNearPageBottom(threshold = 24) {
  const scroller = document.scrollingElement || document.documentElement;
  const maxScroll = scroller.scrollHeight - scroller.clientHeight;
  return maxScroll > 0 && maxScroll - scroller.scrollTop <= threshold;
}

function pinPageBottom(wasNearBottom) {
  if (!wasNearBottom) return;
  const scroller = document.scrollingElement || document.documentElement;
  scroller.scrollTop = scroller.scrollHeight;
}

function keepPageBottomAfterLayout(wasNearBottom) {
  if (!wasNearBottom) return;
  requestAnimationFrame(() => pinPageBottom(true));
}

async function refresh() {
  const wasNearBottom = isNearPageBottom();
  if (liveMode) {
    const now = new Date();
    $('#dateTo').value = fmtDateTime(now);
    if (lastRangeBtn) {
      const from = new Date(now);
      if (lastRangeBtn.dataset.hours) {
        const hours = parseInt(lastRangeBtn.dataset.hours);
        if (timeMode === 'round') {
          from.setHours(now.getHours() - hours + 1, 0, 0, 0);
        } else {
          from.setHours(now.getHours() - hours);
        }
      } else if (lastRangeBtn.dataset.days) {
        const days = parseInt(lastRangeBtn.dataset.days);
        if (timeMode === 'round') {
          from.setDate(now.getDate() - days + 1);
          from.setHours(0, 0, 0, 0);
        } else {
          from.setDate(now.getDate() - days);
        }
      }
      $('#dateFrom').value = fmtDateTime(from);
    }
  }
  const fromInput = $('#dateFrom').value;
  const toInput = $('#dateTo').value;
  const from = fromInput.replace('T', ' ') + ':00';
  const to = toInput.replace('T', ' ') + ':59';
  const now = new Date();
  const interval = currentInterval;
  const source = $('#source').value;
  const baseQ = source ? `&source=${source}` : '';
  const compareQ = activeFilter
    ? (activeFilter.type === 'model'
        ? `&model=${encodeURIComponent(activeFilter.value)}`
        : `&source=${encodeURIComponent(activeFilter.value)}`)
    : '';
  cachedFrom = fromInput;
  cachedTo = toInput;
  cachedInterval = interval;

  const [summary, trend, heatmap, compareSummary, compareTrend, compareHeatmap] = await Promise.all([
    fetch(`/api/tokmon/summary?from=${from}&to=${to}${baseQ}`).then(r => r.json()),
    fetch(`/api/tokmon/trend?interval=${interval}&from=${from}&to=${to}${baseQ}`).then(r => r.json()),
    fetch(`/api/tokmon/heatmap?${baseQ.slice(1)}`).then(r => r.json()),
    activeFilter ? fetch(`/api/tokmon/summary?from=${from}&to=${to}${baseQ}${compareQ}`).then(r => r.json()) : Promise.resolve(null),
    activeFilter ? fetch(`/api/tokmon/trend?interval=${interval}&from=${from}&to=${to}${baseQ}${compareQ}`).then(r => r.json()) : Promise.resolve(null),
    activeFilter ? fetch(`/api/tokmon/heatmap?${baseQ.slice(1)}${compareQ.slice(1)}`).then(r => r.json()) : Promise.resolve(null),
  ]);

  const t = summary.total;
  const costVal = calcCost(summary.byModel);
  cachedAvgRates = calcAvgRates(summary.byModel);
  cachedRawValues = {
    total: t.total_input + t.total_output,
    reqs: t.total_requests,
    input: t.total_input,
    output: t.total_output,
    cache: t.total_cache_creation,
    cacheHit: t.total_cache_read,
    cost: costVal,
  };

  cachedCompareRawValues = compareSummary ? {
    total: compareSummary.total.total_input + compareSummary.total.total_output,
    reqs: compareSummary.total.total_requests,
    input: compareSummary.total.total_input,
    output: compareSummary.total.total_output,
    cache: compareSummary.total.total_cache_creation,
    cacheHit: compareSummary.total.total_cache_read,
    cost: calcCost(compareSummary.byModel),
  } : null;
  updateHero();

  function displayPair(key) {
    const total = key === 'cost' ? fmtCost(cachedRawValues[key]) : num(cachedRawValues[key]);
    if (!cachedCompareRawValues) return total;
    const compare = key === 'cost' ? fmtCost(cachedCompareRawValues[key]) : num(cachedCompareRawValues[key]);
    const cls = SERIES_DEF[key].cls;
    return `<span class="muted-total">${total}</span><span class="value-split">|</span><span class="${cls}">${compare}</span>`;
  }

  const cardValues = {
    total: displayPair('total'),
    reqs: displayPair('reqs'),
    input: displayPair('input'),
    output: displayPair('output'),
    cache: displayPair('cache'),
    cacheHit: displayPair('cacheHit'),
    cost: displayPair('cost'),
  };
  const keys = Object.keys(SERIES_DEF);
  $('#summaryCards').innerHTML = keys.map(k => {
    const d = SERIES_DEF[k];
    const act = k === activeSeries ? ' active' : '';
    return `<div class="card clickable${act}" style="--card-color:${d.color}" onclick="selectSeries('${k}')"><span class="icon">${d.icon}</span><div class="label">${d.label}</div><div class="value ${d.cls}">${cardValues[k]}</div></div>`;
  }).join('');
  pinPageBottom(wasNearBottom);

  const trendLookup = {};
  trend.forEach(r => { trendLookup[r.bucket] = r; });

  const filledTrend = [];
  const fmtLocal = d => {
    const y = d.getFullYear(), m = String(d.getMonth()+1).padStart(2,'0'), dd = String(d.getDate()).padStart(2,'0');
    if (interval === 'day') return `${y}-${m}-${dd}`;
    return `${y}-${m}-${dd} ${String(d.getHours()).padStart(2,'0')}:00`;
  };

  if (interval === 'day') {
    const cur = new Date(fromInput.slice(0, 10) + 'T00:00:00');
    const end = new Date(toInput.slice(0, 10) + 'T00:00:00');
    while (cur <= end) {
      const key = fmtLocal(cur);
      const r = trendLookup[key];
      filledTrend.push([key, r ? r.input_tokens : 0, r ? r.output_tokens : 0, r ? r.cache_creation : 0, r ? r.requests : 0, r ? r.cache_read : 0]);
      cur.setDate(cur.getDate() + 1);
    }
  } else {
    const start = new Date(fromInput + ':00');
    const end = new Date(toInput + ':00');
    const cur = new Date(start);
    while (cur <= end) {
      const key = fmtLocal(cur);
      const r = trendLookup[key];
      filledTrend.push([key, r ? r.input_tokens : 0, r ? r.output_tokens : 0, r ? r.cache_creation : 0, r ? r.requests : 0, r ? r.cache_read : 0]);
      cur.setHours(cur.getHours() + 1);
    }
  }

  cachedTrend = filledTrend;

  if (compareTrend) {
    const compareLookup = {};
    compareTrend.forEach(r => { compareLookup[r.bucket] = r; });
    cachedCompareTrend = filledTrend.map(r => {
      const c = compareLookup[r[0]];
      return [r[0], c ? c.input_tokens : 0, c ? c.output_tokens : 0, c ? c.cache_creation : 0, c ? c.requests : 0, c ? c.cache_read : 0];
    });
  } else {
    cachedCompareTrend = null;
  }

  renderTrend();
  pinPageBottom(wasNearBottom);
  cachedHeatmap = compareHeatmap || heatmap;
  renderHeatmap(cachedHeatmap);
  pinPageBottom(wasNearBottom);

  cachedSummary = summary;
  renderBreakdown();
  pinPageBottom(wasNearBottom);
  await loadRecords();
  pinPageBottom(wasNearBottom);
  keepPageBottomAfterLayout(wasNearBottom);
}

function getMetricValue(r) {
  switch (activeSeries) {
    case 'total': return (r.input_tokens || 0) + (r.output_tokens || 0);
    case 'reqs': return r.requests || 0;
    case 'input': return r.input_tokens || 0;
    case 'output': return r.output_tokens || 0;
    case 'cache': return r.cache_creation || 0;
    case 'cacheHit': return r.cache_read || 0;
    case 'cost': {
      const pricing = loadPricing();
      if (r.model) {
        const p = pricing[r.model];
        if (!p) return 0;
        return (r.input_tokens||0)/1e6*(p.input||0) + (r.output_tokens||0)/1e6*(p.output||0)
             + (r.cache_creation||0)/1e6*(p.cache_create||0) + (r.cache_read||0)/1e6*(p.cache_read||0);
      }
      return (r.input_tokens||0)/1e6*cachedAvgRates.input + (r.output_tokens||0)/1e6*cachedAvgRates.output
           + (r.cache_creation||0)/1e6*cachedAvgRates.cache_create + (r.cache_read||0)/1e6*cachedAvgRates.cache_read;
    }
    default: return 0;
  }
}

function renderBreakdown() {
  if (!cachedSummary) return;
  const srcColors = { 'claude-code': C.orange, 'codex': C.accent };
  const modelColors = [C.accent, C.green, C.orange, C.pink, C.purple];
  const def = SERIES_DEF[activeSeries];
  const metricLabel = def.label;

  if (breakdownTab === 'source') {
    const data = cachedSummary.bySource.slice().sort((a, b) => getMetricValue(b) - getMetricValue(a));
    const total = data.reduce((s, r) => s + getMetricValue(r), 0) || 1;
    pieChart.setOption({
      backgroundColor: 'transparent',
      tooltip: { trigger: 'item', confine: true, ...tt },
      series: [{
        type: 'pie', radius: ['45%', '70%'], center: ['50%', '55%'],
        label: { color: '#8b949e', fontFamily: "'JetBrains Mono', monospace", fontSize: 10,
          formatter: '{b}', overflow: 'truncate', width: 80 },
        labelLine: { length: 8, length2: 6 },
        labelLayout: { hideOverlap: true },
        selectedMode: false,
        data: data.map(r => {
          const isActive = activeFilter?.type === 'source' && activeFilter?.value === r.source;
          const dimmed = activeFilter && !isActive;
          return {
            name: r.source, value: getMetricValue(r),
            itemStyle: { color: srcColors[r.source] || C.purple, opacity: dimmed ? 0.25 : 1 }
          };
        }),
      }],
    }, true);
    pieChart.off('click');
    pieChart.on('click', p => { toggleFilter('source', p.name); });

    $('#breakdownHead').innerHTML = `<tr><th>Source</th><th class="num">${metricLabel}</th><th class="num">Ratio</th></tr>`;
    renderTablePage(data, total, r => {
      const cls = r.source === 'claude-code' ? 'orange' : 'accent';
      return `<td><span class="${cls}">${r.source}</span></td>`;
    }, r => `toggleFilter('source','${r.source}')`);
  } else {
    const data = cachedSummary.byModel.filter(r => r.model && r.model !== 'unknown' && r.model !== '<synthetic>').sort((a, b) => getMetricValue(b) - getMetricValue(a));
    const total = data.reduce((s, r) => s + getMetricValue(r), 0) || 1;
    pieChart.setOption({
      backgroundColor: 'transparent',
      tooltip: { trigger: 'item', confine: true, ...tt },
      series: [{
        type: 'pie', radius: ['45%', '70%'], center: ['50%', '55%'],
        label: { color: '#8b949e', fontFamily: "'JetBrains Mono', monospace", fontSize: 10,
          formatter: '{b}', overflow: 'truncate', width: 80 },
        labelLine: { length: 8, length2: 6 },
        labelLayout: { hideOverlap: true },
        selectedMode: false,
        data: data.map((r, i) => {
          const isActive = activeFilter?.type === 'model' && activeFilter?.value === r.model;
          const dimmed = activeFilter && !isActive;
          return {
            name: r.model, value: getMetricValue(r),
            itemStyle: { color: modelColors[i % modelColors.length], opacity: dimmed ? 0.25 : 1 }
          };
        }),
      }],
    }, true);
    pieChart.off('click');
    pieChart.on('click', p => { toggleFilter('model', p.name); });

    $('#breakdownHead').innerHTML = `<tr><th>Model</th><th>Source</th><th class="num">${metricLabel}</th><th class="num">Ratio</th></tr>`;
    renderTablePage(data, total, r => {
      const cls = r.source === 'claude-code' ? 'orange' : 'accent';
      return `<td>${r.model}</td><td><span class="${cls}">${r.source}</span></td>`;
    }, r => `toggleFilter('model','${r.model}')`);
  }
  pieChart.resize();
}

function renderTablePage(data, total, rowPrefix, rowClickFn) {
  const totalPages = Math.ceil(data.length / PAGE_SIZE);
  if (currentPage >= totalPages) currentPage = Math.max(0, totalPages - 1);
  const start = currentPage * PAGE_SIZE;
  const page = data.slice(start, start + PAGE_SIZE);

  $('#breakdownTable tbody').innerHTML = page.map(r => {
    const v = getMetricValue(r);
    const pct = (v / total * 100).toFixed(1);
    const clickFn = rowClickFn(r);
    let rowCls = '';
    if (activeFilter) {
      const isMatch = (activeFilter.type === 'model' && r.model === activeFilter.value)
                   || (activeFilter.type === 'source' && r.source === activeFilter.value);
      rowCls = isMatch ? ' row-selected' : ' row-dimmed';
    }
    return `<tr class="clickable-row${rowCls}" onclick="${clickFn}">${rowPrefix(r)}<td class="num val">${num(v)}</td><td class="num pct">${pct}%</td></tr>`;
  }).join('');

  const pager = $('#pager');
  if (totalPages <= 1) {
    pager.innerHTML = '';
    return;
  }
  let html = `<button onclick="goPage(${currentPage - 1})" ${currentPage === 0 ? 'disabled' : ''}>&lt;</button>`;
  for (let i = 0; i < totalPages; i++) {
    html += `<button class="${i === currentPage ? 'active' : ''}" onclick="goPage(${i})">${i + 1}</button>`;
  }
  html += `<button onclick="goPage(${currentPage + 1})" ${currentPage >= totalPages - 1 ? 'disabled' : ''}>&gt;</button>`;
  pager.innerHTML = html;
}

function goPage(p) {
  currentPage = p;
  renderBreakdown();
}

function renderHeatmap(data) {
  const LEVELS = ['#1b1f23', '#0e4429', '#006d32', '#26a641', '#39d353'];
  const DAY_LABELS = ['', 'Mon', '', 'Wed', '', 'Fri', ''];
  const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const LEFT = 32, TOP = 20;

  const wrap = $('#heatmapWrap');
  wrap.innerHTML = '';

  const lookup = {};
  data.forEach(r => { lookup[r.day] = getMetricValue(r); });
  const vals = data.map(r => getMetricValue(r));
  const maxVal = Math.max(...vals, 1);
  const metricLabel = SERIES_DEF[activeSeries].label;

  function level(n) {
    if (n === 0) return 0;
    const q = n / maxVal;
    if (q <= 0.25) return 1;
    if (q <= 0.5) return 2;
    if (q <= 0.75) return 3;
    return 4;
  }

  const availW = wrap.clientWidth - LEFT - 10;
  const availH = wrap.clientHeight || 0;

  // 1. 纵向：用高度算出 STEP，让 7 天填满纵轴
  let STEP;
  if (availH > 100) {
    STEP = Math.floor((availH - TOP - 10) / 7);
  } else {
    STEP = Math.floor(availW / 53);
  }
  STEP = Math.max(STEP, 8);

  // 2. 横向：用 STEP 算能放多少周，决定日期范围
  const maxWeeks = Math.floor(availW / STEP);
  const totalDays = Math.min(Math.max(maxWeeks, 1) * 7, 365);

  const end = new Date();
  const start = new Date(end);
  start.setDate(end.getDate() - totalDays + 1);
  start.setDate(start.getDate() - start.getDay());

  const weeks = [];
  let cur = new Date(start);
  let week = [];
  while (cur <= end) {
    week.push(new Date(cur));
    if (week.length === 7) { weeks.push(week); week = []; }
    cur.setDate(cur.getDate() + 1);
  }
  if (week.length) weeks.push(week);

  const GAP = Math.max(Math.round(STEP * 0.22), 2);
  const CELL = STEP - GAP;
  const fontSize = Math.max(Math.round(CELL * 0.85), 8);

  const w = LEFT + weeks.length * STEP + 10;
  const h = TOP + 7 * STEP + 10;

  let svg = `<svg width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg">`;

  for (let d = 0; d < 7; d++) {
    if (DAY_LABELS[d]) {
      svg += `<text class="day-label" x="${LEFT - 4}" y="${TOP + d * STEP + CELL - 1}" text-anchor="end" font-size="${fontSize}">${DAY_LABELS[d]}</text>`;
    }
  }

  let lastMonth = -1;
  weeks.forEach((wk, wi) => {
    const m = wk[0].getMonth();
    if (m !== lastMonth) {
      svg += `<text class="month-label" x="${LEFT + wi * STEP}" y="${TOP - 5}" font-size="${fontSize}">${MONTHS[m]}</text>`;
      lastMonth = m;
    }
    wk.forEach(day => {
      const dow = day.getDay();
      const key = fmtDate(day);
      const n = lookup[key] || 0;
      const color = LEVELS[level(n)];
      const x = LEFT + wi * STEP;
      const y = TOP + dow * STEP;
      const stroke = n === 0 ? ' stroke="#21262d" stroke-width="1"' : '';
      svg += `<rect x="${x}" y="${y}" width="${CELL}" height="${CELL}" rx="2" ry="2" fill="${color}"${stroke} data-date="${key}" data-count="${n}"/>`;
    });
  });

  svg += '</svg>';
  wrap.innerHTML = svg;

  let tip = document.querySelector('.heatmap-tooltip');
  if (!tip) { tip = document.createElement('div'); tip.className = 'heatmap-tooltip'; document.body.appendChild(tip); }

  wrap.addEventListener('mouseover', e => {
    const rect = e.target.closest('rect');
    if (!rect) return;
    tip.innerHTML = `<b>${num(parseInt(rect.dataset.count))}</b> ${SERIES_DEF[activeSeries].label.toLowerCase()} on ${rect.dataset.date}`;
    tip.style.display = 'block';
  });
  wrap.addEventListener('mousemove', e => {
    const tipW = tip.offsetWidth || 150;
    const tipH = tip.offsetHeight || 30;
    let x = e.clientX + 12;
    let y = e.clientY - tipH - 8;
    if (x + tipW > window.innerWidth - 8) x = e.clientX - tipW - 12;
    if (y < 8) y = e.clientY + 16;
    tip.style.left = x + 'px';
    tip.style.top = y + 'px';
  });
  wrap.addEventListener('mouseout', e => {
    if (e.target.tagName === 'rect') tip.style.display = 'none';
  });
}

document.querySelector('.rbtn[data-days="7"]').click();

let refreshTimer = null;
function startAutoRefresh() {
  if (refreshTimer) clearInterval(refreshTimer);
  const ms = parseInt($('#refreshRate').value);
  if (!ms) return;
  refreshTimer = setInterval(() => {
    if (liveMode) refresh();
  }, ms);
}
$('#refreshRate').addEventListener('change', startAutoRefresh);
startAutoRefresh();

let recordsPage = 0;
const RECORDS_PER_PAGE = 20;

async function loadRecords() {
  let q = `page=${recordsPage}&limit=${RECORDS_PER_PAGE}`;
  if (activeFilter) {
    if (activeFilter.type === 'model') q += `&model=${encodeURIComponent(activeFilter.value)}`;
    else if (activeFilter.type === 'source') q += `&source=${encodeURIComponent(activeFilter.value)}`;
  }
  const source = $('#source').value;
  if (source) q += `&source=${encodeURIComponent(source)}`;

  const data = await fetch(`/api/tokmon/records?${q}`).then(r => r.json());
  const tbody = $('#recordsTable tbody');
  tbody.innerHTML = data.rows.map(r => {
    const srcCls = r.source === 'claude-code' ? 'orange' : 'accent';
    const time = r.created_at.replace('T', ' ').slice(0, 16);
    return `<tr>
      <td>${time}</td>
      <td><span class="${srcCls}">${r.source}</span></td>
      <td>${r.model}</td>
      <td class="num">${num(r.input_tokens)}</td>
      <td class="num">${num(r.output_tokens)}</td>
      <td class="num">${num(r.cache_creation)}</td>
      <td class="num">${num(r.cache_read)}</td>
    </tr>`;
  }).join('') || '<tr><td colspan="7" style="text-align:center;color:var(--text-dim)">No records</td></tr>';

  const totalPages = Math.ceil(data.total / RECORDS_PER_PAGE);
  const pager = $('#recordsPager');
  if (totalPages <= 1) { pager.innerHTML = ''; return; }

  const maxBtns = 5;
  let startP = Math.max(0, recordsPage - Math.floor(maxBtns / 2));
  let endP = Math.min(totalPages, startP + maxBtns);
  if (endP - startP < maxBtns) startP = Math.max(0, endP - maxBtns);

  let html = `<button onclick="goRecordsPage(0)" ${recordsPage === 0 ? 'disabled' : ''}>&laquo;</button>`;
  html += `<button onclick="goRecordsPage(${recordsPage - 1})" ${recordsPage === 0 ? 'disabled' : ''}>&lt;</button>`;
  for (let i = startP; i < endP; i++) {
    html += `<button class="${i === recordsPage ? 'active' : ''}" onclick="goRecordsPage(${i})">${i + 1}</button>`;
  }
  html += `<button onclick="goRecordsPage(${recordsPage + 1})" ${recordsPage >= totalPages - 1 ? 'disabled' : ''}>&gt;</button>`;
  html += `<button onclick="goRecordsPage(${totalPages - 1})" ${recordsPage >= totalPages - 1 ? 'disabled' : ''}>&raquo;</button>`;
  pager.innerHTML = html;

  $('#recordsPageInfo').textContent = `${recordsPage + 1} / ${totalPages}`;
  $('#recordsJump').max = totalPages;
}

function goRecordsPage(p) {
  recordsPage = Math.max(0, p);
  loadRecords();
}

$('#recordsJump').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    const v = parseInt(e.target.value);
    if (v >= 1) { goRecordsPage(v - 1); e.target.value = ''; }
  }
});
