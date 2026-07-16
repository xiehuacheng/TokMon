"""
TokMon Web - Scanner
扫描各 AI coding agent 的本地日志，提取 token 用量，存入 SQLite。
"""
import os, sys, json, sqlite3, time, re, glob, pyzstd
from pathlib import Path
from datetime import datetime, timezone

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "web", "tokmon.db")

SCANNER_VERSION = 1

SOURCES = {
    "claude": {
        "name": "Claude Code",
        "paths": [
            os.path.expanduser("~/.claude/projects"),
            os.path.expanduser("~/.claude"),
        ],
        "patterns": ["**/*.jsonl", "**/*.jsonl.zst"],
    },
    "codex": {
        "name": "Codex",
        "paths": [
            os.path.expanduser("~/.codex"),
        ],
        "patterns": ["**/sessions/**/*.jsonl", "**/archived_sessions/**/*.jsonl", "**/*.jsonl.zst"],
    },
    "kimi": {
        "name": "Kimi Code",
        "paths": [
            os.path.expanduser("~/.kimi-code"),
        ],
        "patterns": ["**/wire.jsonl"],
    },
    "qwen": {
        "name": "Qwen Code",
        "paths": [
            os.path.expanduser("~/.qwen/projects"),
        ],
        "patterns": ["**/*.jsonl"],
    },
    "opencode": {
        "name": "OpenCode",
        "paths": [
            os.path.expanduser("~/.local/share/opencode"),
        ],
        "patterns": ["**/*.db", "**/*.sqlite"],
    },
}

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS usage_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            session_id TEXT,
            session_name TEXT,
            model TEXT,
            request_id TEXT,
            input_tokens INTEGER DEFAULT 0,
            output_tokens INTEGER DEFAULT 0,
            cache_created INTEGER DEFAULT 0,
            cache_read INTEGER DEFAULT 0,
            total_tokens INTEGER DEFAULT 0,
            requests INTEGER DEFAULT 1,
            timestamp INTEGER,
            created_at TEXT DEFAULT (datetime('now'))
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS tokmon_scan_state (
            source TEXT PRIMARY KEY,
            file_path TEXT,
            offset INTEGER DEFAULT 0,
            mtime REAL DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.commit()
    conn.close()

def read_jsonl(filepath):
    """Read .jsonl or .jsonl.zst file, yield parsed lines."""
    if filepath.endswith(".zst"):
        try:
            with open(filepath, "rb") as f:
                dctx = pyzstd.ZstdDecompressor()
                reader = dctx.stream_reader(f)
                text = reader.read().decode("utf-8", errors="replace")
                for line in text.split("\n"):
                    line = line.strip()
                    if line:
                        try:
                            yield json.loads(line)
                        except json.JSONDecodeError:
                            pass
        except Exception as e:
            print(f"  Error reading {filepath}: {e}", file=sys.stderr)
    else:
        try:
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            yield json.loads(line)
                        except json.JSONDecodeError:
                            pass
        except Exception as e:
            print(f"  Error reading {filepath}: {e}", file=sys.stderr)

def extract_claude_record(obj):
    """Extract token usage from a Claude Code log entry."""
    rec = {
        "session_id": None, "session_name": None, "model": None,
        "request_id": None, "input_tokens": 0, "output_tokens": 0,
        "cache_created": 0, "cache_read": 0, "total_tokens": 0,
        "timestamp": None,
    }
    # Try to find usage field
    usage = None
    if isinstance(obj, dict):
        usage = obj.get("usage")
        if usage and isinstance(usage, dict):
            rec["input_tokens"] = usage.get("input_tokens", 0)
            rec["output_tokens"] = usage.get("output_tokens", 0)
            rec["cache_created"] = usage.get("cache_creation_input_tokens", 0)
            rec["cache_read"] = usage.get("cache_read_input_tokens", 0)
            rec["total_tokens"] = usage.get("output_tokens", 0) + usage.get("input_tokens", 0)
        rec["model"] = obj.get("model") or obj.get("model_id")
        rec["request_id"] = obj.get("message_id") or obj.get("id")
        rec["session_id"] = obj.get("session_id")
        rec["timestamp"] = obj.get("timestamp") or obj.get("created_at")
        # Session name
        if obj.get("project"):
            rec["session_name"] = obj["project"].get("name") or obj["project"].get("path")
        elif obj.get("cwd"):
            rec["session_name"] = os.path.basename(obj["cwd"])
    return rec

def extract_codex_record(obj):
    """Extract token usage from Codex log entry."""
    rec = {
        "session_id": None, "session_name": None, "model": None,
        "request_id": None, "input_tokens": 0, "output_tokens": 0,
        "cache_created": 0, "cache_read": 0, "total_tokens": 0,
        "timestamp": None,
    }
    if not isinstance(obj, dict):
        return rec
    usage = obj.get("usage") or obj.get("token_usage")
    if usage and isinstance(usage, dict):
        rec["input_tokens"] = usage.get("prompt_tokens", 0) or usage.get("input_tokens", 0)
        rec["output_tokens"] = usage.get("completion_tokens", 0) or usage.get("output_tokens", 0)
        rec["total_tokens"] = usage.get("total_tokens", rec["input_tokens"] + rec["output_tokens"])
    rec["model"] = obj.get("model") or obj.get("model_id")
    rec["request_id"] = obj.get("id") or obj.get("request_id")
    rec["session_id"] = obj.get("session_id")
    rec["timestamp"] = obj.get("timestamp") or obj.get("created_at")
    rec["session_name"] = obj.get("session_name") or obj.get("title")
    return rec

def extract_generic_record(obj):
    """Generic extraction - look for common token field names."""
    rec = {
        "session_id": None, "session_name": None, "model": None,
        "request_id": None, "input_tokens": 0, "output_tokens": 0,
        "cache_created": 0, "cache_read": 0, "total_tokens": 0,
        "timestamp": None,
    }
    if not isinstance(obj, dict):
        return rec
    # Try common field names
    for field in ["model", "model_id"]:
        if obj.get(field):
            rec["model"] = obj[field]
            break
    for field in ["input_tokens", "prompt_tokens", "inputTokens"]:
        if obj.get(field):
            rec["input_tokens"] = obj[field]
            break
    for field in ["output_tokens", "completion_tokens", "outputTokens"]:
        if obj.get(field):
            rec["output_tokens"] = obj[field]
            break
    rec["total_tokens"] = rec["input_tokens"] + rec["output_tokens"]
    rec["request_id"] = obj.get("id") or obj.get("request_id") or obj.get("message_id")
    rec["session_id"] = obj.get("session_id") or obj.get("sessionId")
    rec["timestamp"] = obj.get("timestamp") or obj.get("created_at") or obj.get("time")
    rec["session_name"] = obj.get("session_name") or obj.get("title") or obj.get("name")
    return rec

EXTRACTORS = {
    "claude": extract_claude_record,
    "codex": extract_codex_record,
}

def scan_source(source_key, conn):
    """Scan files for a given source, insert new records."""
    source_config = SOURCES.get(source_key)
    if not source_config:
        return 0
    extractor = EXTRACTORS.get(source_key, extract_generic_record)
    count = 0
    c = conn.cursor()
    for base_path in source_config["paths"]:
        if not os.path.isdir(base_path):
            continue
        for pattern in source_config["patterns"]:
            for filepath in glob.glob(os.path.join(base_path, pattern), recursive=True):
                if not os.path.isfile(filepath):
                    continue
                mtime = os.path.getmtime(filepath)
                # Check scan state
                c.execute("SELECT offset, mtime FROM tokmon_scan_state WHERE file_path = ?", (filepath,))
                row = c.fetchone()
                if row and row[1] >= mtime and row[0] > 0:
                    continue  # Already scanned, no changes
                offset = row[0] if row else 0
                # Read and process lines
                line_num = 0
                for obj in read_jsonl(filepath):
                    line_num += 1
                    if line_num <= offset:
                        continue
                    rec = extractor(obj)
                    if rec["total_tokens"] > 0 or rec["input_tokens"] > 0:
                        ts = rec["timestamp"]
                        if ts:
                            try:
                                if isinstance(ts, (int, float)):
                                    dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                                else:
                                    dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
                                ts_int = int(dt.timestamp())
                            except Exception:
                                ts_int = int(time.time())
                        else:
                            ts_int = int(time.time())
                        c.execute("""
                            INSERT OR REPLACE INTO usage_records
                            (source, session_id, session_name, model, request_id,
                             input_tokens, output_tokens, cache_created, cache_read,
                             total_tokens, requests, timestamp)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                        """, (
                            source_key,
                            rec["session_id"], rec["session_name"], rec["model"], rec["request_id"],
                            rec["input_tokens"], rec["output_tokens"],
                            rec["cache_created"], rec["cache_read"],
                            rec["total_tokens"], ts_int,
                        ))
                        count += 1
                # Update scan state
                c.execute("""
                    INSERT OR REPLACE INTO tokmon_scan_state (source, file_path, offset, mtime, updated_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                """, (source_key, filepath, line_num, mtime))
                if line_num > 0:
                    conn.commit()
                    print(f"  {filepath}: {line_num} lines, {count} new records")
    return count

def full_scan():
    init_db()
    conn = sqlite3.connect(DB_PATH)
    total = 0
    for source_key in SOURCES:
        print(f"Scanning {source_key}...")
        n = scan_source(source_key, conn)
        total += n
        print(f"  -> {n} new records")
    conn.close()
    print(f"\nTotal: {total} new records inserted.")
    return total

if __name__ == "__main__":
    full_scan()
