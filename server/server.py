#!/usr/bin/env python3
"""7Go backend – SQLite + Sign-in-with-Apple + ntfy/APNs notifications."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import time
import uuid
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Any
from urllib import error as urlerror, parse as urlparse, request as urlrequest

ROOT = Path(__file__).resolve().parent
DB   = ROOT / "7go.db"
NTFY = os.environ.get("NTFY_BASE", "https://ntfy.sh").rstrip("/")
HOST = os.environ.get("SIGNAL_HOST", "0.0.0.0")
PORT = int(os.environ.get("SIGNAL_PORT", "8787"))

# Rate limiting: max requests per window
RATE_LIMIT_WINDOW = 60  # seconds
RATE_LIMIT_MAX_SIGNAL = 30  # max signals per minute
RATE_LIMIT_MAX_REGISTER = 10  # max registrations per minute


# ──────────────────────────────────────────────
# Rate Limiter
# ──────────────────────────────────────────────

class RateLimiter:
    def __init__(self) -> None:
        self._lock = Lock()
        self._requests: dict[str, list[float]] = defaultdict(list)

    def is_allowed(self, key: str, max_requests: int, window: int = RATE_LIMIT_WINDOW) -> bool:
        now = time.time()
        with self._lock:
            self._requests[key] = [t for t in self._requests[key] if now - t < window]
            if len(self._requests[key]) >= max_requests:
                return False
            self._requests[key].append(now)
            return True


rate_limiter = RateLimiter()


# ──────────────────────────────────────────────
# DB
# ──────────────────────────────────────────────

def init_db() -> None:
    with _conn() as c:
        c.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id           TEXT PRIMARY KEY,
                apple_id     TEXT UNIQUE NOT NULL,
                display_name TEXT NOT NULL,
                ntfy_topic   TEXT UNIQUE NOT NULL,
                created_at   TEXT DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token      TEXT PRIMARY KEY,
                user_id    TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now')),
                expires_at TEXT DEFAULT (datetime('now', '+30 days'))
            );
            CREATE TABLE IF NOT EXISTS friends (
                user_id   TEXT NOT NULL,
                friend_id TEXT NOT NULL,
                PRIMARY KEY (user_id, friend_id)
            );
            CREATE TABLE IF NOT EXISTS device_tokens (
                user_id      TEXT NOT NULL,
                device_token TEXT NOT NULL,
                platform     TEXT NOT NULL DEFAULT 'ios',
                updated_at   TEXT DEFAULT (datetime('now')),
                PRIMARY KEY (user_id, device_token)
            );
            CREATE TABLE IF NOT EXISTS signal_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                sender_id  TEXT NOT NULL,
                target_id  TEXT NOT NULL,
                pattern    TEXT DEFAULT 'ツンツン',
                sent_at    TEXT DEFAULT (datetime('now'))
            );
        """)


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA foreign_keys=ON")
    return c


def user_by_token(token: str) -> dict | None:
    with _conn() as c:
        row = c.execute(
            """SELECT u.* FROM users u
               JOIN sessions s ON s.user_id = u.id
               WHERE s.token = ?
               AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))""",
            (token,),
        ).fetchone()
    return dict(row) if row else None


# ──────────────────────────────────────────────
# Handler
# ──────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "7Go/2.0"

    def do_GET(self) -> None:
        p = self.path.split("?")[0]
        if p == "/health":
            self.ok({"ok": True, "version": "2.0"})
        elif p == "/users/search":
            self.search_users()
        elif p == "/friends":
            self.get_friends()
        else:
            self.err(404, "Not found")

    def do_POST(self) -> None:
        if self.path == "/register":
            self.register()
        elif self.path == "/friends/add":
            self.add_friend()
        elif self.path == "/signal":
            self.send_signal()
        elif self.path == "/device-token":
            self.register_device_token()
        else:
            self.err(404, "Not found")

    def do_DELETE(self) -> None:
        m = re.match(r"^/friends/([a-f0-9\-]+)$", self.path)
        if m:
            self.remove_friend(m.group(1))
        else:
            self.err(404, "Not found")

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    # ── endpoints ──

    def register(self) -> None:
        ip = self.client_address[0]
        if not rate_limiter.is_allowed(f"register:{ip}", RATE_LIMIT_MAX_REGISTER):
            self.err(429, "Too many requests. Please try again later.")
            return

        body     = self.json_body()
        apple_id = _sanitize(body.get("appleId", ""))
        name     = _sanitize(body.get("displayName", ""))

        if not apple_id:
            self.err(400, "appleId required")
            return

        if len(apple_id) > 256 or len(name) > 100:
            self.err(400, "Input too long")
            return

        with _conn() as c:
            row = c.execute("SELECT * FROM users WHERE apple_id = ?", (apple_id,)).fetchone()
            if row is None:
                uid   = str(uuid.uuid4())
                topic = f"7go-{uuid.uuid4().hex[:20]}"
                c.execute(
                    "INSERT INTO users (id, apple_id, display_name, ntfy_topic) VALUES (?,?,?,?)",
                    (uid, apple_id, name or "名無し", topic),
                )
                row = c.execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()
            elif name:
                c.execute("UPDATE users SET display_name = ? WHERE id = ?", (name, row["id"]))

            token = str(uuid.uuid4())
            c.execute("INSERT INTO sessions (token, user_id) VALUES (?,?)", (token, row["id"]))

        self.ok({
            "sessionToken": token,
            "userId":       row["id"],
            "displayName":  name if name else row["display_name"],
            "ntfyTopic":    row["ntfy_topic"],
        })

    def search_users(self) -> None:
        me = self.auth()
        if not me:
            return
        q = _sanitize(urlparse.parse_qs(self.path.partition("?")[2]).get("q", [""])[0])
        if not q or len(q) > 50:
            self.ok([])
            return

        # Use parameterized LIKE to prevent SQL injection
        with _conn() as c:
            rows = c.execute(
                "SELECT id, display_name FROM users WHERE display_name LIKE ? ESCAPE '\\' AND id != ? LIMIT 20",
                (_escape_like(q), me["id"]),
            ).fetchall()
        self.ok([{"id": r["id"], "displayName": r["display_name"]} for r in rows])

    def get_friends(self) -> None:
        me = self.auth()
        if not me:
            return
        with _conn() as c:
            rows = c.execute(
                """SELECT u.id, u.display_name FROM users u
                   JOIN friends f ON f.friend_id = u.id
                   WHERE f.user_id = ?""",
                (me["id"],),
            ).fetchall()
        self.ok([{"id": r["id"], "displayName": r["display_name"]} for r in rows])

    def add_friend(self) -> None:
        me = self.auth()
        if not me:
            return
        fid = _sanitize(self.json_body().get("friendId", ""))
        if not fid:
            self.err(400, "friendId required")
            return
        if fid == me["id"]:
            self.err(400, "Cannot add yourself as a friend")
            return
        with _conn() as c:
            # Verify friend exists
            friend = c.execute("SELECT id FROM users WHERE id = ?", (fid,)).fetchone()
            if not friend:
                self.err(404, "User not found")
                return
            try:
                c.execute("INSERT INTO friends (user_id, friend_id) VALUES (?,?)", (me["id"], fid))
            except sqlite3.IntegrityError:
                pass
        self.ok({"ok": True})

    def remove_friend(self, friend_id: str) -> None:
        me = self.auth()
        if not me:
            return
        friend_id = _sanitize(friend_id)
        if not friend_id:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            c.execute("DELETE FROM friends WHERE user_id = ? AND friend_id = ?", (me["id"], friend_id))
        self.ok({"ok": True})

    def send_signal(self) -> None:
        me = self.auth()
        if not me:
            return

        if not rate_limiter.is_allowed(f"signal:{me['id']}", RATE_LIMIT_MAX_SIGNAL):
            self.err(429, "送信が速すぎます。少し待ってからお試しください。")
            return

        body = self.json_body()
        fid = _sanitize(body.get("friendId", ""))
        pattern = _sanitize(body.get("pattern", "ツンツン"))[:20]

        if not fid:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            friend = c.execute("SELECT * FROM users WHERE id = ?", (fid,)).fetchone()
            if not friend:
                self.err(404, "Friend not found")
                return

            # Verify they are actually friends
            is_friend = c.execute(
                "SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?",
                (me["id"], fid),
            ).fetchone()
            if not is_friend:
                self.err(403, "Not a friend")
                return

            # Log the signal
            c.execute(
                "INSERT INTO signal_log (sender_id, target_id, pattern) VALUES (?,?,?)",
                (me["id"], fid, pattern),
            )

        # Send notification
        try:
            _publish_ntfy(
                topic=friend["ntfy_topic"],
                sender=me["display_name"],
                pattern=pattern,
                message=f"{me['display_name']} が {pattern}",
            )
        except urlerror.HTTPError as e:
            self.err(502, f"ntfy error: {e.code}")
            return
        except urlerror.URLError as e:
            self.err(502, f"ntfy unreachable: {e.reason}")
            return

        self.ok({"delivered": True, "detail": f"Signal sent to {friend['display_name']}."})

    def register_device_token(self) -> None:
        me = self.auth()
        if not me:
            return
        body = self.json_body()
        device_token = _sanitize(body.get("deviceToken", ""))
        platform = _sanitize(body.get("platform", "ios"))

        if not device_token:
            self.err(400, "deviceToken required")
            return
        if len(device_token) > 256:
            self.err(400, "deviceToken too long")
            return

        with _conn() as c:
            c.execute(
                """INSERT INTO device_tokens (user_id, device_token, platform, updated_at)
                   VALUES (?, ?, ?, datetime('now'))
                   ON CONFLICT(user_id, device_token) DO UPDATE SET updated_at = datetime('now')""",
                (me["id"], device_token, platform),
            )
        self.ok({"ok": True})

    # ── helpers ──

    def auth(self) -> dict | None:
        token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        if not token:
            self.err(401, "Unauthorized")
            return None
        me = user_by_token(token)
        if not me:
            self.err(401, "Unauthorized")
        return me

    def json_body(self) -> dict[str, Any]:
        n = int(self.headers.get("Content-Length", 0))
        if n > 10240:  # 10KB max body
            return {}
        return json.loads(self.rfile.read(n)) if n > 0 else {}

    def ok(self, payload: Any) -> None:
        self._json(200, payload)

    def err(self, code: int, msg: str) -> None:
        self._json(code, {"error": msg})

    def _json(self, code: int, payload: Any) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[7go] {self.address_string()} {fmt % args}")


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _sanitize(value: str | None) -> str:
    """Strip whitespace and control characters."""
    if not value:
        return ""
    return re.sub(r"[\x00-\x1f\x7f]", "", str(value).strip())


def _escape_like(value: str) -> str:
    """Escape special characters in LIKE patterns to prevent injection."""
    escaped = value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


# ──────────────────────────────────────────────
# ntfy
# ──────────────────────────────────────────────

def _publish_ntfy(topic: str, sender: str, pattern: str, message: str) -> None:
    req = urlrequest.Request(
        f"{NTFY}/{topic}",
        data=message.encode(),
        headers={
            "Content-Type": "text/plain; charset=utf-8",
            "Title":    f"7Go — {sender}",
            "Priority": "urgent",
            "Tags":     "wave",
            "Actions":  json.dumps([]),
        },
        method="POST",
    )
    with urlrequest.urlopen(req, timeout=10):
        pass


# ──────────────────────────────────────────────
# main
# ──────────────────────────────────────────────

def main() -> None:
    init_db()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"7Go server   http://{HOST}:{PORT}")
    print(f"ntfy base    {NTFY}")
    print(f"Rate limits  signal={RATE_LIMIT_MAX_SIGNAL}/min  register={RATE_LIMIT_MAX_REGISTER}/min")
    srv.serve_forever()


if __name__ == "__main__":
    main()
