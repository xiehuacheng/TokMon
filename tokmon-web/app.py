"""
TokMon Web - Flask Backend
提供前端页面 + JSON API
"""
import os, sys, json, sqlite3, time
from datetime import datetime, timezone
from flask import Flask, jsonify, render_template, request, send_from_directory

app_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(app_dir, "scanner"))
DB_PATH = os.path.join(app_dir, "tokmon.db")

app = Flask(__name__, static_folder="static")
app.config["JSON_AS_ASCII"] = False

MODEL_PRICING = {
    "claude-3.5-sonnet": {"input": 3.0, "output": 15.0, "cache_create": 3.75, "cache_read": 0.30},
    "claude-3-opus": {"input": 15.0, "output": 75.0, "cache_create": 18.75, "cache_read": 1.50},
    "claude-3-haiku": {"input": 0.25, "output": 1.25, "cache_create": 0.30, "cache_read": 0.03},
    "gpt-4o": {"input": 2.5, "output": 10.0, "cache_create": 2.5, "cache_read": 1.25},
    "gpt-4o-mini": {"input": 0.15, "output": 0.60, "cache_create": 0.15, "cache_read": 0.075},
    "default": {"input": 1.0, "output": 3.0, "cache_create": 1.0, "cache_read": 0.50},
}

def get_db():
    if not os.path.exists(DB_PATH):
        return None
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def time_range_filter(conn, range_type="all"):
    """Build WHERE clause for time range."""
    now = int(time.time())
    if range_type == "today":
        start = int(datetime(now, tz=timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        return f"AND timestamp >= {start}"
    elif range_type == "week":
        start = now - 7 * 86400
        return f"AND timestamp >= {start}"
    elif range_type == "month":
        start = now - 30 * 86400
        return f"AND timestamp >= {start}"
    return ""

@app.route("/")
def index():
    return send_from_directory(app.static_folder, "index.html")

@app.route("/api/summary")
def api_summary():
    range_type = request.args.get("range", "all")
    conn = get_db()
    if not conn:
        return jsonify({"total_tokens": 0, "total_requests": 0, "total_input": 0, "total_output": 0, "total_cache_created": 0, "total_cache_read": 0, "est_cost": 0, "by_source": {}})
    where = time_range_filter(conn, range_type)
    row = conn.execute(f"""
        SELECT
            COALESCE(SUM(total_tokens), 0) as total_tokens,
            COALESCE(SUM(requests), 0) as total_requests,
            COALESCE(SUM(input_tokens), 0) as total_input,
            COALESCE(SUM(output_tokens), 0) as total_output,
            COALESCE(SUM(cache_created), 0) as total_cache_created,
            COALESCE(SUM(cache_read), 0) as total_cache_read
        FROM usage_records WHERE 1=1 {where}
    """).fetchone()
    by_source = {}
    for srow in conn.execute(f"SELECT source, SUM(total_tokens) as tokens, SUM(requests) as reqs FROM usage_records WHERE 1=1 {where} GROUP BY source"):
        by_source[srow["source"]] = {"tokens": srow["tokens"] or 0, "requests": srow["reqs"] or 0}
    conn.close()
    return jsonify({
        "total_tokens": row["total_tokens"],
        "total_requests": row["total_requests"],
        "total_input": row["total_input"],
        "total_output": row["total_output"],
        "total_cache_created": row["total_cache_created"],
        "total_cache_read": row["total_cache_read"],
        "est_cost": 0,  # Could calculate with model pricing
        "by_source": by_source,
    })

@app.route("/api/trend")
def api_trend():
    range_type = request.args.get("range", "week")
    conn = get_db()
    if not conn:
        return jsonify([])
    where = time_range_filter(conn, range_type)
    rows = conn.execute(f"""
        SELECT date(timestamp, 'unixepoch') as day, SUM(total_tokens) as tokens, SUM(requests) as reqs
        FROM usage_records WHERE 1=1 {where}
        GROUP BY day ORDER BY day
    """).fetchall()
    conn.close()
    return jsonify([{"day": r["day"], "tokens": r["tokens"] or 0, "requests": r["reqs"] or 0} for r in rows])

@app.route("/api/heatmap")
def api_heatmap():
    """Activity heatmap: hour of day x day of week."""
    conn = get_db()
    if not conn:
        return jsonify({})
    rows = conn.execute("""
        SELECT
            strftime('%H', timestamp, 'unixepoch') as hour,
            strftime('%w', timestamp, 'unixepoch') as dow,
            COUNT(*) as count,
            SUM(total_tokens) as tokens
        FROM usage_records
        GROUP BY hour, dow
    """).fetchall()
    conn.close()
    result = {}
    for r in rows:
        key = f"{r['hour']}-{r['dow']}"
        result[key] = {"count": r["count"], "tokens": r["tokens"] or 0}
    return jsonify(result)

@app.route("/api/requests")
def api_requests():
    range_type = request.args.get("range", "week")
    search = request.args.get("search", "").strip()
    page = int(request.args.get("page", 1))
    per_page = 50
    conn = get_db()
    if not conn:
        return jsonify({"data": [], "total": 0})
    where = time_range_filter(conn, range_type)
    if search:
        where += f" AND (model LIKE '%{search}%' OR session_name LIKE '%{search}%' OR session_id LIKE '%{search}%')"
    total = conn.execute(f"SELECT COUNT(*) as c FROM usage_records WHERE 1=1 {where}").fetchone()["c"]
    rows = conn.execute(f"""
        SELECT id, source, session_id, session_name, model, input_tokens, output_tokens,
               cache_created, cache_read, total_tokens, requests, timestamp
        FROM usage_records WHERE 1=1 {where}
        ORDER BY timestamp DESC LIMIT {per_page} OFFSET {(page-1)*per_page}
    """).fetchall()
    conn.close()
    return jsonify({
        "data": [dict(r) for r in rows],
        "total": total,
        "page": page,
        "per_page": per_page,
    })

@app.route("/api/sessions")
def api_sessions():
    range_type = request.args.get("range", "week")
    search = request.args.get("search", "").strip()
    conn = get_db()
    if not conn:
        return jsonify({"data": []})
    where = time_range_filter(conn, range_type)
    if search:
        where += f" AND (session_name LIKE '%{search}%' OR session_id LIKE '%{search}%')"
    rows = conn.execute(f"""
        SELECT session_id, session_name, source,
               COUNT(*) as requests,
               SUM(total_tokens) as total_tokens,
               SUM(input_tokens) as total_input,
               SUM(output_tokens) as total_output,
               MIN(timestamp) as first_seen,
               MAX(timestamp) as last_seen
        FROM usage_records
        WHERE session_id IS NOT NULL AND session_id != '' {where}
        GROUP BY session_id, source
        ORDER BY last_seen DESC
        LIMIT 100
    """).fetchall()
    conn.close()
    return jsonify({"data": [dict(r) for r in rows]})

@app.route("/api/distribution")
def api_distribution():
    conn = get_db()
    if not conn:
        return jsonify({"by_source": [], "by_model": []})
    by_source = [dict(r) for r in conn.execute("SELECT source, SUM(total_tokens) as tokens FROM usage_records GROUP BY source ORDER BY tokens DESC")]
    by_model = [dict(r) for r in conn.execute("SELECT model, SUM(total_tokens) as tokens FROM usage_records GROUP BY model ORDER BY tokens DESC LIMIT 20")]
    conn.close()
    return jsonify({"by_source": by_source, "by_model": by_model})

@app.route("/api/scan", methods=["POST"])
def api_scan():
    from scanner.scanner import full_scan
    try:
        count = full_scan()
        return jsonify({"status": "ok", "new_records": count})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/api/sources")
def api_sources():
    """Return configured sources and their data paths."""
    sources = [
        {"key": "claude", "name": "Claude Code", "icon": "🤖", "path": os.path.expanduser("~/.claude")},
        {"key": "codex", "name": "Codex", "icon": "⚡", "path": os.path.expanduser("~/.codex")},
        {"key": "kimi", "name": "Kimi Code", "icon": "🌟", "path": os.path.expanduser("~/.kimi-code")},
        {"key": "qwen", "name": "Qwen Code", "icon": "🔮", "path": os.path.expanduser("~/.qwen")},
        {"key": "opencode", "name": "OpenCode", "icon": "🔓", "path": os.path.expanduser("~/.local/share/opencode")},
    ]
    for s in sources:
        s["exists"] = os.path.isdir(s["path"])
    return jsonify(sources)

@app.route("/api/models")
def api_models():
    return jsonify(MODEL_PRICING)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7899, debug=False)
