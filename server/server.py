#!/usr/bin/env python3
"""7Go backend – SQLite + Sign-in-with-Apple + ntfy notifications."""

from __future__ import annotations

import json
import os
import sqlite3
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import error as urlerror, parse as urlparse, request as urlrequest

ROOT = Path(__file__).resolve().parent
DB   = ROOT / "7go.db"
NTFY = os.environ.get("NTFY_BASE", "https://ntfy.sh").rstrip("/")
HOST = os.environ.get("SIGNAL_HOST", "0.0.0.0")
PORT = int(os.environ.get("SIGNAL_PORT", "8787"))


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
                created_at TEXT DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS friends (
                user_id   TEXT NOT NULL,
                friend_id TEXT NOT NULL,
                PRIMARY KEY (user_id, friend_id)
            );
        """)


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c


def user_by_token(token: str) -> dict | None:
    with _conn() as c:
        row = c.execute(
            "SELECT u.* FROM users u JOIN sessions s ON s.user_id = u.id WHERE s.token = ?",
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
            self.ok({"ok": True})
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
        else:
            self.err(404, "Not found")

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    # ── endpoints ──

    def register(self) -> None:
        body     = self.json_body()
        apple_id = (body.get("appleId") or "").strip()
        name     = (body.get("displayName") or "").strip()

        if not apple_id:
            self.err(400, "appleId required")
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
                # Apple は初回サインインのみ名前を返す。提供された場合のみ更新
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
        q = urlparse.parse_qs(self.path.partition("?")[2]).get("q", [""])[0].strip()
        if not q:
            self.ok([])
            return
        with _conn() as c:
            rows = c.execute(
                "SELECT id, display_name FROM users WHERE display_name LIKE ? AND id != ? LIMIT 20",
                (f"%{q}%", me["id"]),
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
        fid = (self.json_body().get("friendId") or "").strip()
        if not fid:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            try:
                c.execute("INSERT INTO friends (user_id, friend_id) VALUES (?,?)", (me["id"], fid))
            except sqlite3.IntegrityError:
                pass
        self.ok({"ok": True})

    def send_signal(self) -> None:
        me = self.auth()
        if not me:
            return
        fid = (self.json_body().get("friendId") or "").strip()
        if not fid:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            friend = c.execute("SELECT * FROM users WHERE id = ?", (fid,)).fetchone()
        if not friend:
            self.err(404, "Friend not found")
            return

        try:
            _publish_ntfy(
                topic=friend["ntfy_topic"],
                sender=me["display_name"],
                message=f"{me['display_name']} がコンビニ行こうって言ってるよ ☕",
            )
        except urlerror.HTTPError as e:
            self.err(502, f"ntfy error: {e.code}")
            return
        except urlerror.URLError as e:
            self.err(502, f"ntfy unreachable: {e.reason}")
            return

        self.ok({"delivered": True, "detail": f"Signal sent to {friend['display_name']}."})

    # ── helpers ──

    def auth(self) -> dict | None:
        token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        me    = user_by_token(token)
        if not me:
            self.err(401, "Unauthorized")
        return me

    def json_body(self) -> dict[str, Any]:
        n = int(self.headers.get("Content-Length", 0))
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

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[7go] {self.address_string()} {fmt % args}")


# ──────────────────────────────────────────────
# ntfy
# ──────────────────────────────────────────────

def _publish_ntfy(topic: str, sender: str, message: str) -> None:
    req = urlrequest.Request(
        f"{NTFY}/{topic}",
        data=message.encode(),
        headers={
            "Content-Type": "text/plain; charset=utf-8",
            "Title":    f"7Go — {sender}",
            "Priority": "urgent",
            "Tags":     "wave",
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
    srv.serve_forever()


if __name__ == "__main__":
    main()
