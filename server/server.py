#!/usr/bin/env python3
"""7Go backend – SQLite + Sign-in-with-Apple + polling-based signals."""

from __future__ import annotations

import json
import os
import re
import sqlite3
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import parse as urlparse

ROOT = Path(__file__).resolve().parent
DB   = Path(os.environ.get("DB_PATH", str(ROOT / "7go.db")))
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
            CREATE TABLE IF NOT EXISTS signals (
                id          TEXT PRIMARY KEY,
                sender_id   TEXT NOT NULL,
                receiver_id TEXT NOT NULL,
                sender_name TEXT NOT NULL,
                created_at  TEXT DEFAULT (datetime('now')),
                read         INTEGER DEFAULT 0
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
    server_version = "7Go/3.0"

    def do_GET(self) -> None:
        p = self.path.split("?")[0]
        if p == "/health":
            self.ok({"ok": True})
        elif p == "/privacy":
            self.privacy_policy()
        elif p == "/users/search":
            self.search_users()
        elif p == "/friends":
            self.get_friends()
        elif p == "/signals/pending":
            self.get_pending_signals()
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

    def do_DELETE(self) -> None:
        if self.path == "/account":
            self.delete_account()
            return

        m = re.match(r"^/friends/([^/]+)$", self.path)
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
        body     = self.json_body()
        apple_id = (body.get("appleId") or "").strip()
        name     = (body.get("displayName") or "").strip()

        if not apple_id:
            self.err(400, "appleId required")
            return

        with _conn() as c:
            row = c.execute("SELECT * FROM users WHERE apple_id = ?", (apple_id,)).fetchone()
            if row is None:
                uid = str(uuid.uuid4())
                c.execute(
                    "INSERT INTO users (id, apple_id, display_name) VALUES (?,?,?)",
                    (uid, apple_id, name or "名無し"),
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
        if fid == me["id"]:
            self.err(400, "Cannot add yourself")
            return
        with _conn() as c:
            target = c.execute("SELECT id FROM users WHERE id = ?", (fid,)).fetchone()
            if not target:
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
        friend_id = friend_id.strip()
        if not friend_id:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            c.execute("DELETE FROM friends WHERE user_id = ? AND friend_id = ?", (me["id"], friend_id))
        self.ok({"ok": True})

    def delete_account(self) -> None:
        me = self.auth()
        if not me:
            return

        with _conn() as c:
            c.execute("DELETE FROM signals WHERE sender_id = ? OR receiver_id = ?", (me["id"], me["id"]))
            c.execute("DELETE FROM friends WHERE user_id = ? OR friend_id = ?", (me["id"], me["id"]))
            c.execute("DELETE FROM sessions WHERE user_id = ?", (me["id"],))
            c.execute("DELETE FROM users WHERE id = ?", (me["id"],))

        self.ok({"deleted": True})

    def send_signal(self) -> None:
        me = self.auth()
        if not me:
            return
        fid = (self.json_body().get("friendId") or "").strip()
        if not fid:
            self.err(400, "friendId required")
            return
        with _conn() as c:
            is_friend = c.execute(
                "SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?",
                (me["id"], fid),
            ).fetchone()
            if not is_friend:
                self.err(403, "Not a friend")
                return
            friend = c.execute("SELECT * FROM users WHERE id = ?", (fid,)).fetchone()
            if not friend:
                self.err(404, "Friend not found")
                return

            signal_id = str(uuid.uuid4())
            c.execute(
                "INSERT INTO signals (id, sender_id, receiver_id, sender_name) VALUES (?,?,?,?)",
                (signal_id, me["id"], fid, me["display_name"]),
            )

        self.ok({"delivered": True, "detail": f"Signal sent to {friend['display_name']}."})

    def get_pending_signals(self) -> None:
        me = self.auth()
        if not me:
            return
        with _conn() as c:
            rows = c.execute(
                """SELECT id, sender_id, sender_name, created_at FROM signals
                   WHERE receiver_id = ? AND read = 0
                   ORDER BY created_at DESC LIMIT 50""",
                (me["id"],),
            ).fetchall()
            if rows:
                ids = [r["id"] for r in rows]
                placeholders = ",".join("?" * len(ids))
                c.execute(f"UPDATE signals SET read = 1 WHERE id IN ({placeholders})", ids)
        self.ok([{
            "id": r["id"],
            "senderId": r["sender_id"],
            "senderName": r["sender_name"],
            "createdAt": r["created_at"],
        } for r in rows])

    # ── helpers ──

    def auth(self) -> dict | None:
        token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        me    = user_by_token(token)
        if not me:
            self.err(401, "Unauthorized")
        return me

    def privacy_policy(self) -> None:
        updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>7Go Privacy Policy</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f7f7f2;
      --card: #ffffff;
      --text: #1f2937;
      --muted: #6b7280;
      --accent: #0f766e;
      --border: #d1d5db;
    }}
    body {{
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.7;
    }}
    main {{
      max-width: 760px;
      margin: 0 auto;
      padding: 32px 20px 56px;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 24px;
      box-shadow: 0 18px 40px rgba(15, 23, 42, 0.05);
    }}
    h1, h2 {{
      line-height: 1.25;
    }}
    h1 {{
      margin-top: 0;
      margin-bottom: 8px;
      font-size: 32px;
    }}
    h2 {{
      margin-top: 28px;
      margin-bottom: 8px;
      font-size: 20px;
    }}
    p, li {{
      font-size: 16px;
    }}
    .meta {{
      color: var(--muted);
      margin-bottom: 24px;
    }}
    a {{
      color: var(--accent);
    }}
  </style>
</head>
<body>
  <main>
    <div class="card">
      <h1>7Go プライバシーポリシー</h1>
      <p class="meta">最終更新日: {updated_at}</p>
      <p>7Go は、ユーザー同士でシグナルを送り合うために必要な最小限の情報のみを取り扱います。</p>

      <h2>取得する情報</h2>
      <ul>
        <li>Sign in with Apple で受け取る識別子</li>
        <li>表示名</li>
        <li>ログイン状態を維持するためのセッショントークン</li>
        <li>友達追加によって作成される友達関係データ</li>
        <li>送受信したシグナル情報</li>
      </ul>

      <h2>利用目的</h2>
      <ul>
        <li>アカウント作成とログイン状態の維持</li>
        <li>友達検索、友達追加、友達一覧の表示</li>
        <li>指定した相手へのシグナル送信</li>
        <li>不正利用や障害対応のための最小限の運用</li>
      </ul>

      <h2>保存と削除</h2>
      <p>アカウント情報は、サービス提供に必要な期間保存されます。アプリ内の「設定」からアカウント削除を実行すると、プロフィール、友達関係、シグナル履歴、サーバー上のセッション情報を削除します。</p>

      <h2>お問い合わせ</h2>
      <p>サポート窓口は App Store の掲載情報をご確認ください。</p>
    </div>
  </main>
</body>
</html>
"""
        self._html(200, html)

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

    def _html(self, code: int, body: str) -> None:
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[7go] {self.address_string()} {fmt % args}")


# ──────────────────────────────────────────────
# main
# ──────────────────────────────────────────────

def main() -> None:
    init_db()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"7Go server   http://{HOST}:{PORT}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
