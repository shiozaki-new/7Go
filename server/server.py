#!/usr/bin/env python3
"""7Go4 backend – pairing codes, emoji signals, device registration, and APNs delivery."""

from __future__ import annotations

import json
import os
import re
import secrets
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import parse as urlparse
from urllib.request import Request, urlopen

try:
    import httpx
except ImportError:  # pragma: no cover - optional until APNs is configured
    httpx = None

try:
    import jwt
except ImportError:  # pragma: no cover - optional until APNs is configured
    jwt = None

ROOT = Path(__file__).resolve().parent
HOST = os.environ.get("SIGNAL_HOST", "0.0.0.0")
PORT = int(os.environ.get("SIGNAL_PORT", "8787"))

# Turso (libSQL) connection settings
TURSO_URL = os.environ.get("TURSO_URL", "")
TURSO_TOKEN = os.environ.get("TURSO_TOKEN", "")

# APNs settings
APNS_KEY_ID = os.environ.get("APNS_KEY_ID", "")
APNS_TEAM_ID = os.environ.get("APNS_TEAM_ID", "")
APNS_PRIVATE_KEY = os.environ.get("APNS_PRIVATE_KEY", "")
APNS_PRIVATE_KEY_PATH = os.environ.get("APNS_PRIVATE_KEY_PATH", "")
APNS_USE_SANDBOX = os.environ.get("APNS_USE_SANDBOX", "1").lower() in {"1", "true", "yes", "on"}

PAIR_CODE_LENGTH = 6
MAX_PENDING_SIGNALS = 100
ALLOWED_EMOJIS = {
    "🏪",
    "☕️",
    "🍽️",
    "🚻",
    "🏠",
    "🏢",
    "🏫",
    "🤫",
    "🚑",
}
DEFAULT_EMOJI = "☕️"


# ──────────────────────────────────────────────
# Turso HTTP API wrapper
# ──────────────────────────────────────────────

class TursoRow:
    """sqlite3.Row-compatible wrapper for Turso HTTP API results."""

    def __init__(self, columns: list[str], values: list[Any]):
        self._data = dict(zip(columns, values))

    def __getitem__(self, key: str) -> Any:
        return self._data[key]

    def keys(self):
        return self._data.keys()


class TursoCursor:
    """Minimal cursor returned by TursoConnection.execute()."""

    def __init__(self, columns: list[str], rows: list[list[Any]]):
        self._columns = columns
        self._rows = [TursoRow(columns, row) for row in rows]

    def fetchone(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return self._rows


class TursoConnection:
    """sqlite3.Connection-compatible wrapper using Turso HTTP API."""

    def __init__(self, base_url: str, token: str):
        self._url = base_url.rstrip("/") + "/v2/pipeline"
        self._token = token

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def _request(self, statements: list[dict[str, Any]]) -> list[dict[str, Any]]:
        body = {
            "requests": [{"type": "execute", "stmt": stmt} for stmt in statements] + [{"type": "close"}]
        }
        req = Request(
            self._url,
            data=json.dumps(body).encode(),
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
            },
        )
        with urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())["results"]

    def execute(self, sql: str, params=None) -> TursoCursor:
        stmt: dict[str, Any] = {"sql": sql}
        if params:
            if isinstance(params, (list, tuple)):
                stmt["args"] = [
                    {"type": _turso_type(value), "value": None if value is None else str(value)}
                    for value in params
                ]
            else:
                stmt["named_args"] = [
                    {"name": key, "type": _turso_type(value), "value": None if value is None else str(value)}
                    for key, value in params.items()
                ]

        result = self._request([stmt])[0]
        if result["type"] == "error":
            msg = result["error"].get("message", "")
            lower = msg.lower()
            if "unique constraint failed" in lower or "primary key constraint failed" in lower:
                raise sqlite3.IntegrityError(msg)
            raise RuntimeError(msg)

        response = result["response"]["result"]
        columns = [column["name"] for column in response.get("cols", [])]
        rows = [[cell["value"] for cell in row] for row in response.get("rows", [])]
        return TursoCursor(columns, rows)

    def executescript(self, script: str):
        statements = [statement.strip() for statement in script.split(";") if statement.strip()]
        if not statements:
            return
        results = self._request([{"sql": statement} for statement in statements])
        for result in results:
            if result["type"] == "error":
                raise RuntimeError(result["error"].get("message", ""))


def _turso_type(value: Any) -> str:
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "float"
    if value is None:
        return "null"
    return "text"


# ──────────────────────────────────────────────
# APNs client
# ──────────────────────────────────────────────

class APNsClient:
    """Small APNs provider using token auth."""

    def __init__(self) -> None:
        self._cached_token = ""
        self._cached_token_expires_at = 0.0
        self._http = httpx.Client(http2=True, timeout=10.0) if httpx else None

    def configured(self) -> bool:
        return bool(self._http and jwt and APNS_KEY_ID and APNS_TEAM_ID and self._private_key())

    def push_signal(
        self,
        *,
        device_token: str,
        push_topic: str,
        sender_id: str,
        sender_name: str,
        emoji: str,
        signal_id: str,
        created_at: str,
    ) -> tuple[bool, str]:
        if not self.configured():
            return False, "apns not configured"

        url = f"{self._base_url()}/3/device/{device_token}"
        payload = {
            "aps": {
                "alert": {
                    "title": sender_name,
                    "body": emoji,
                },
                "sound": "default",
                "category": "SIGNAL_RECEIVED",
                "thread-id": f"pager-{sender_id}",
                "interruption-level": "time-sensitive",
            },
            "signalId": signal_id,
            "senderId": sender_id,
            "senderName": sender_name,
            "emoji": emoji,
            "createdAt": created_at,
        }
        headers = {
            "authorization": f"bearer {self._provider_token()}",
            "apns-topic": push_topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-expiration": "0",
            "content-type": "application/json",
        }

        try:
            response = self._http.post(url, headers=headers, json=payload)
        except Exception as exc:  # pragma: no cover - transport failures vary
            return False, f"transport error: {exc}"

        if 200 <= response.status_code < 300:
            return True, "delivered"

        detail = response.text.strip() or response.reason_phrase
        return False, f"{response.status_code}: {detail}"

    def _provider_token(self) -> str:
        now = time.time()
        if self._cached_token and now < self._cached_token_expires_at:
            return self._cached_token

        payload = {
            "iss": APNS_TEAM_ID,
            "iat": int(now),
        }
        token = jwt.encode(
            payload,
            self._private_key(),
            algorithm="ES256",
            headers={"kid": APNS_KEY_ID},
        )
        self._cached_token = token
        self._cached_token_expires_at = now + 50 * 60
        return token

    def _private_key(self) -> str:
        if APNS_PRIVATE_KEY_PATH:
            return Path(APNS_PRIVATE_KEY_PATH).read_text(encoding="utf-8")
        return APNS_PRIVATE_KEY.replace("\\n", "\n").strip()

    def _base_url(self) -> str:
        if APNS_USE_SANDBOX:
            return "https://api.sandbox.push.apple.com"
        return "https://api.push.apple.com"


apns = APNsClient()


# ──────────────────────────────────────────────
# DB
# ──────────────────────────────────────────────

_INIT_STATEMENTS = [
    """CREATE TABLE IF NOT EXISTS users (
        id           TEXT PRIMARY KEY,
        apple_id     TEXT UNIQUE NOT NULL,
        display_name TEXT NOT NULL,
        created_at   TEXT DEFAULT (datetime('now'))
    )""",
    """CREATE TABLE IF NOT EXISTS sessions (
        token      TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
    )""",
    """CREATE TABLE IF NOT EXISTS friends (
        user_id   TEXT NOT NULL,
        friend_id TEXT NOT NULL,
        PRIMARY KEY (user_id, friend_id)
    )""",
    """CREATE TABLE IF NOT EXISTS signals (
        id          TEXT PRIMARY KEY,
        sender_id   TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        sender_name TEXT NOT NULL,
        emoji       TEXT NOT NULL DEFAULT '☕️',
        created_at  TEXT DEFAULT (datetime('now')),
        read        INTEGER DEFAULT 0
    )""",
    """CREATE TABLE IF NOT EXISTS pair_codes (
        user_id     TEXT PRIMARY KEY,
        code        TEXT UNIQUE NOT NULL,
        created_at  TEXT DEFAULT (datetime('now')),
        refreshed_at TEXT DEFAULT (datetime('now'))
    )""",
    """CREATE TABLE IF NOT EXISTS devices (
        token       TEXT PRIMARY KEY,
        user_id      TEXT NOT NULL,
        platform     TEXT NOT NULL,
        device_kind  TEXT NOT NULL,
        push_topic   TEXT NOT NULL,
        created_at   TEXT DEFAULT (datetime('now')),
        updated_at   TEXT DEFAULT (datetime('now'))
    )""",
]


def init_db() -> None:
    with _conn() as conn:
        for statement in _INIT_STATEMENTS:
            conn.execute(statement)
        ensure_signal_schema(conn)


def ensure_signal_schema(conn) -> None:
    _ensure_column(conn, "signals", "emoji", "TEXT NOT NULL DEFAULT '☕️'")


def _ensure_column(conn, table: str, column: str, definition: str) -> None:
    try:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")
    except (RuntimeError, sqlite3.OperationalError) as exc:
        message = str(exc).lower()
        if "duplicate column" in message or "already exists" in message:
            return
        raise


def _conn():
    if TURSO_URL:
        http_url = TURSO_URL.replace("libsql://", "https://")
        return TursoConnection(http_url, TURSO_TOKEN)
    conn = sqlite3.connect(str(ROOT / "7go.db"))
    conn.row_factory = sqlite3.Row
    return conn


def user_by_token(token: str) -> dict[str, Any] | None:
    with _conn() as conn:
        row = conn.execute(
            "SELECT u.* FROM users u JOIN sessions s ON s.user_id = u.id WHERE s.token = ?",
            (token,),
        ).fetchone()
    return dict(row) if row else None


def ensure_pair_code(conn, user_id: str) -> str:
    existing = conn.execute(
        "SELECT code FROM pair_codes WHERE user_id = ?",
        (user_id,),
    ).fetchone()
    if existing:
        return str(existing["code"]).zfill(PAIR_CODE_LENGTH)

    for _ in range(128):
        code = f"{secrets.randbelow(10 ** PAIR_CODE_LENGTH):0{PAIR_CODE_LENGTH}d}"
        collision = conn.execute("SELECT user_id FROM pair_codes WHERE code = ?", (code,)).fetchone()
        if collision:
            continue
        conn.execute(
            "INSERT INTO pair_codes (user_id, code) VALUES (?, ?)",
            (user_id, code),
        )
        return code

    raise RuntimeError("Could not generate a unique pairing code")


def normalize_pair_code(raw_code: str) -> str:
    digits = "".join(character for character in raw_code if character.isdigit())
    return digits[:PAIR_CODE_LENGTH]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def validate_emoji(raw_value: str) -> str:
    candidate = (raw_value or "").strip()
    if candidate in ALLOWED_EMOJIS:
        return candidate
    return DEFAULT_EMOJI


def table_columns(conn, table: str) -> set[str]:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    names: set[str] = set()
    for row in rows:
        if isinstance(row, sqlite3.Row):
            names.add(str(row["name"]))
        elif isinstance(row, TursoRow):
            names.add(str(row["name"]))
        else:
            names.add(str(row[1]))
    return names


def legacy_ntfy_topic(user_id: str) -> str:
    return f"legacy-{user_id}"


def register_device_for_user(
    conn,
    *,
    user_id: str,
    token: str,
    platform: str,
    device_kind: str,
    push_topic: str,
) -> None:
    existing = conn.execute("SELECT token FROM devices WHERE token = ?", (token,)).fetchone()
    if existing:
        conn.execute(
            """UPDATE devices
               SET user_id = ?, platform = ?, device_kind = ?, push_topic = ?, updated_at = datetime('now')
               WHERE token = ?""",
            (user_id, platform, device_kind, push_topic, token),
        )
        return

    conn.execute(
        """INSERT INTO devices (token, user_id, platform, device_kind, push_topic)
           VALUES (?, ?, ?, ?, ?)""",
        (token, user_id, platform, device_kind, push_topic),
    )


def deliver_signal_to_devices(
    *,
    receiver_id: str,
    sender_id: str,
    sender_name: str,
    emoji: str,
    signal_id: str,
    created_at: str,
) -> list[dict[str, Any]]:
    with _conn() as conn:
        rows = conn.execute(
            """SELECT token, device_kind, push_topic
               FROM devices
               WHERE user_id = ?
               ORDER BY CASE device_kind WHEN 'watch' THEN 0 ELSE 1 END, updated_at DESC""",
            (receiver_id,),
        ).fetchall()

    attempts: list[dict[str, Any]] = []
    for row in rows:
        ok, detail = apns.push_signal(
            device_token=row["token"],
            push_topic=row["push_topic"],
            sender_id=sender_id,
            sender_name=sender_name,
            emoji=emoji,
            signal_id=signal_id,
            created_at=created_at,
        )
        attempts.append(
            {
                "deviceKind": row["device_kind"],
                "delivered": ok,
                "detail": detail,
            }
        )
    return attempts


# ──────────────────────────────────────────────
# Handler
# ──────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "7Go4/4.0"

    def do_GET(self) -> None:
        path = self.path.split("?")[0]
        if path == "/health":
            self.ok({"ok": True, "apnsConfigured": apns.configured()})
        elif path == "/privacy":
            self.privacy_policy()
        elif path == "/users/search":
            self.search_users()
        elif path == "/friends":
            self.get_friends()
        elif path == "/signals/pending":
            self.get_pending_signals()
        elif path == "/pairing-code":
            self.get_pairing_code()
        else:
            self.err(404, "Not found")

    def do_POST(self) -> None:
        if self.path == "/register":
            self.register()
        elif self.path == "/friends/add":
            self.add_friend()
        elif self.path == "/signal":
            self.send_signal()
        elif self.path == "/pair":
            self.redeem_pair_code()
        elif self.path == "/devices/register":
            self.register_device()
        else:
            self.err(404, "Not found")

    def do_DELETE(self) -> None:
        if self.path == "/account":
            self.delete_account()
            return

        match = re.match(r"^/friends/([^/]+)$", self.path)
        if match:
            self.remove_friend(match.group(1))
        else:
            self.err(404, "Not found")

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    # ── endpoints ──

    def register(self) -> None:
        body = self.json_body()
        apple_id = (body.get("appleId") or "").strip()
        display_name = (body.get("displayName") or "").strip()

        if not apple_id:
            self.err(400, "appleId required")
            return

        with _conn() as conn:
            user_columns = table_columns(conn, "users")
            row = conn.execute(
                "SELECT * FROM users WHERE apple_id = ?",
                (apple_id,),
            ).fetchone()

            if row is None:
                user_id = str(uuid.uuid4())
                if "ntfy_topic" in user_columns:
                    conn.execute(
                        "INSERT INTO users (id, apple_id, display_name, ntfy_topic) VALUES (?, ?, ?, ?)",
                        (user_id, apple_id, display_name or "名無し", legacy_ntfy_topic(user_id)),
                    )
                else:
                    conn.execute(
                        "INSERT INTO users (id, apple_id, display_name) VALUES (?, ?, ?)",
                        (user_id, apple_id, display_name or "名無し"),
                    )
                row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            elif display_name:
                conn.execute(
                    "UPDATE users SET display_name = ? WHERE id = ?",
                    (display_name, row["id"]),
                )
                row = conn.execute("SELECT * FROM users WHERE id = ?", (row["id"],)).fetchone()

            session_token = str(uuid.uuid4())
            conn.execute(
                "INSERT INTO sessions (token, user_id) VALUES (?, ?)",
                (session_token, row["id"]),
            )
            pair_code = ensure_pair_code(conn, row["id"])

        self.ok(
            {
                "sessionToken": session_token,
                "userId": row["id"],
                "displayName": row["display_name"],
                "pairingCode": pair_code,
            }
        )

    def search_users(self) -> None:
        me = self.auth()
        if not me:
            return

        query = urlparse.parse_qs(self.path.partition("?")[2]).get("q", [""])[0].strip()
        if not query:
            self.ok([])
            return

        with _conn() as conn:
            rows = conn.execute(
                "SELECT id, display_name FROM users WHERE display_name LIKE ? AND id != ? LIMIT 20",
                (f"%{query}%", me["id"]),
            ).fetchall()
        self.ok([{"id": row["id"], "displayName": row["display_name"]} for row in rows])

    def get_pairing_code(self) -> None:
        me = self.auth()
        if not me:
            return

        with _conn() as conn:
            code = ensure_pair_code(conn, me["id"])
        self.ok({"code": code})

    def redeem_pair_code(self) -> None:
        me = self.auth()
        if not me:
            return

        code = normalize_pair_code((self.json_body().get("code") or "").strip())
        if len(code) != PAIR_CODE_LENGTH:
            self.err(400, "A 6-digit code is required")
            return

        with _conn() as conn:
            my_code = ensure_pair_code(conn, me["id"])
            if code == my_code:
                self.err(400, "Cannot pair with your own code")
                return

            target = conn.execute(
                """SELECT u.id, u.display_name
                   FROM pair_codes p
                   JOIN users u ON u.id = p.user_id
                   WHERE p.code = ?""",
                (code,),
            ).fetchone()
            if not target:
                self.err(404, "Pairing code not found")
                return

            conn.execute(
                "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
                (me["id"], target["id"]),
            )
            conn.execute(
                "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
                (target["id"], me["id"]),
            )

        self.ok({"id": target["id"], "displayName": target["display_name"]})

    def get_friends(self) -> None:
        me = self.auth()
        if not me:
            return

        with _conn() as conn:
            rows = conn.execute(
                """SELECT u.id, u.display_name
                   FROM users u
                   JOIN friends f ON f.friend_id = u.id
                   WHERE f.user_id = ?
                   ORDER BY u.display_name COLLATE NOCASE""",
                (me["id"],),
            ).fetchall()
        self.ok([{"id": row["id"], "displayName": row["display_name"]} for row in rows])

    def add_friend(self) -> None:
        me = self.auth()
        if not me:
            return

        friend_id = (self.json_body().get("friendId") or "").strip()
        if not friend_id:
            self.err(400, "friendId required")
            return
        if friend_id == me["id"]:
            self.err(400, "Cannot add yourself")
            return

        with _conn() as conn:
            target = conn.execute("SELECT id FROM users WHERE id = ?", (friend_id,)).fetchone()
            if not target:
                self.err(404, "User not found")
                return
            conn.execute(
                "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
                (me["id"], friend_id),
            )
            conn.execute(
                "INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)",
                (friend_id, me["id"]),
            )
        self.ok({"ok": True})

    def remove_friend(self, friend_id: str) -> None:
        me = self.auth()
        if not me:
            return

        friend_id = friend_id.strip()
        if not friend_id:
            self.err(400, "friendId required")
            return

        with _conn() as conn:
            conn.execute(
                "DELETE FROM friends WHERE user_id = ? AND friend_id = ?",
                (me["id"], friend_id),
            )
            conn.execute(
                "DELETE FROM friends WHERE user_id = ? AND friend_id = ?",
                (friend_id, me["id"]),
            )
        self.ok({"ok": True})

    def register_device(self) -> None:
        me = self.auth()
        if not me:
            return

        body = self.json_body()
        push_token = (body.get("pushToken") or "").strip()
        platform = (body.get("platform") or "").strip().lower() or "unknown"
        device_kind = (body.get("deviceKind") or "").strip().lower() or platform
        push_topic = (body.get("pushTopic") or "").strip()

        if not push_token or not push_topic:
            self.err(400, "pushToken and pushTopic are required")
            return

        with _conn() as conn:
            register_device_for_user(
                conn,
                user_id=me["id"],
                token=push_token,
                platform=platform,
                device_kind=device_kind,
                push_topic=push_topic,
            )

        self.ok({"registered": True, "apnsConfigured": apns.configured()})

    def delete_account(self) -> None:
        me = self.auth()
        if not me:
            return

        with _conn() as conn:
            conn.execute("DELETE FROM signals WHERE sender_id = ? OR receiver_id = ?", (me["id"], me["id"]))
            conn.execute("DELETE FROM friends WHERE user_id = ? OR friend_id = ?", (me["id"], me["id"]))
            conn.execute("DELETE FROM devices WHERE user_id = ?", (me["id"],))
            conn.execute("DELETE FROM pair_codes WHERE user_id = ?", (me["id"],))
            conn.execute("DELETE FROM sessions WHERE user_id = ?", (me["id"],))
            conn.execute("DELETE FROM users WHERE id = ?", (me["id"],))

        self.ok({"deleted": True})

    def send_signal(self) -> None:
        me = self.auth()
        if not me:
            return

        body = self.json_body()
        friend_id = (body.get("friendId") or "").strip()
        emoji = validate_emoji(body.get("emoji") or "")
        if not friend_id:
            self.err(400, "friendId required")
            return

        with _conn() as conn:
            is_friend = conn.execute(
                "SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?",
                (me["id"], friend_id),
            ).fetchone()
            if not is_friend:
                self.err(403, "Not paired")
                return

            friend = conn.execute(
                "SELECT id, display_name FROM users WHERE id = ?",
                (friend_id,),
            ).fetchone()
            if not friend:
                self.err(404, "Friend not found")
                return

            signal_id = str(uuid.uuid4())
            created_at = now_iso()
            conn.execute(
                """INSERT INTO signals (id, sender_id, receiver_id, sender_name, emoji, created_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (signal_id, me["id"], friend_id, me["display_name"], emoji, created_at),
            )

            # Keep only the latest N pending rows per receiver.
            stale_rows = conn.execute(
                """SELECT id FROM signals
                   WHERE receiver_id = ? AND read = 0
                   ORDER BY created_at DESC
                   LIMIT -1 OFFSET ?""",
                (friend_id, MAX_PENDING_SIGNALS),
            ).fetchall()
            if stale_rows:
                placeholders = ",".join("?" * len(stale_rows))
                conn.execute(
                    f"UPDATE signals SET read = 1 WHERE id IN ({placeholders})",
                    [row["id"] for row in stale_rows],
                )

        deliveries = deliver_signal_to_devices(
            receiver_id=friend_id,
            sender_id=me["id"],
            sender_name=me["display_name"],
            emoji=emoji,
            signal_id=signal_id,
            created_at=created_at,
        )
        self.ok(
            {
                "delivered": True,
                "detail": f"Signal sent to {friend['display_name']}.",
                "emoji": emoji,
                "pushAttempts": deliveries,
            }
        )

    def get_pending_signals(self) -> None:
        me = self.auth()
        if not me:
            return

        rows: list[Any] = []
        with _conn() as conn:
            rows = conn.execute(
                """SELECT id, sender_id, sender_name, emoji, created_at
                   FROM signals
                   WHERE receiver_id = ? AND read = 0
                   ORDER BY created_at DESC
                   LIMIT ?""",
                (me["id"], MAX_PENDING_SIGNALS),
            ).fetchall()

            if rows:
                ids = [row["id"] for row in rows]
                placeholders = ",".join("?" * len(ids))
                conn.execute(f"UPDATE signals SET read = 1 WHERE id IN ({placeholders})", ids)

        self.ok(
            [
                {
                    "id": row["id"],
                    "senderId": row["sender_id"],
                    "senderName": row["sender_name"],
                    "emoji": row["emoji"],
                    "createdAt": row["created_at"],
                }
                for row in rows
            ]
        )

    # ── helpers ──

    def auth(self) -> dict[str, Any] | None:
        token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        me = user_by_token(token)
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
  <title>7Go4 Privacy Policy</title>
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
      <h1>7Go4 プライバシーポリシー</h1>
      <p class="meta">最終更新日: {updated_at}</p>
      <p>7Go4 は、ユーザー同士で触覚シグナルを送り合うために必要な最小限の情報のみを取り扱います。</p>

      <h2>取得する情報</h2>
      <ul>
        <li>Sign in with Apple で受け取る識別子</li>
        <li>表示名</li>
        <li>ペアコードとペア関係</li>
        <li>ログイン状態を維持するためのセッショントークン</li>
        <li>通知配信のために必要なデバイストークン</li>
        <li>送受信した絵文字シグナル情報</li>
      </ul>

      <h2>利用目的</h2>
      <ul>
        <li>アカウント作成とログイン状態の維持</li>
        <li>ペアリング、相手一覧の表示</li>
        <li>指定した相手への絵文字シグナル送信</li>
        <li>Apple Watch / iPhone への通知配信</li>
        <li>不正利用や障害対応のための最小限の運用</li>
      </ul>

      <h2>保存と削除</h2>
      <p>アカウント情報は、サービス提供に必要な期間保存されます。アプリ内の「設定」からアカウント削除を実行すると、プロフィール、ペア関係、保留中のシグナル、デバイストークン、サーバー上のセッション情報を削除します。</p>

      <h2>お問い合わせ</h2>
      <p>サポート窓口は App Store の掲載情報をご確認ください。</p>
    </div>
  </main>
</body>
</html>
"""
        self._html(200, html)

    def json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length)) if length > 0 else {}

    def ok(self, payload: Any) -> None:
        self._json(200, payload)

    def err(self, code: int, message: str) -> None:
        self._json(code, {"error": message})

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
        print(f"[7go4] {self.address_string()} {fmt % args}")


# ──────────────────────────────────────────────
# main
# ──────────────────────────────────────────────

def main() -> None:
    init_db()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"7Go4 server   http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
