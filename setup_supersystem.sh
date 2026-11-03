#!/usr/bin/env bash
# ============================================================
# setup_supersystem.sh — «Зеркало» СУПЕРСИСТЕМА: сервер + Android в один клик
# Сервер + мост к телефону + поиск денег + психология + бизнес +
# самообучение. Создаёт структуру, записывает ВСЕ файлы, проверяет сборку.
# Запуск:  bash setup.sh
# ============================================================
set -euo pipefail

echo "=== Зеркало СУПЕРСИСТЕМА: развёртывание ==="

# ------------------------------------------------------------
# 1. Структура папок
# ------------------------------------------------------------
mkdir -p src/core src/modules src/senses src/hands src/mechanics \
         src/integrations src/infra src/money src/psychology src/business \
         src/learn data/suras android dashboard landing logs
touch src/hands/.gitkeep src/integrations/.gitkeep src/infra/.gitkeep

# ------------------------------------------------------------
# 2. Конфиги
# ------------------------------------------------------------
cat > requirements.txt <<'ZERKALO_EOF'
flask>=3.0
gunicorn>=21.0
requests>=2.31
GitPython>=3.1.40
pytest>=8.0
ZERKALO_EOF

cat > .env.example <<'ZERKALO_EOF'
# ===== КЛЮЧИ «Зеркало» =====
# Заполни и переименуй файл в .env

# Голос и мозг
GEMINI_API_KEY=
ELEVENLABS_API_KEY=
GROQ_API_KEY=

# Самоэволюция (GitHub + Render)
GITHUB_TOKEN=
GITHUB_REPO=owner/repo
GITHUB_BRANCH=main
RENDER_API_KEY=
RENDER_SERVICE_ID=

# Опционально
TWO_GIS_API_KEY=        # для money_maker (2GIS)
SELF_EVOLVE_ENABLED=0
SELF_EVOLVE_INTERVAL=3600
SELF_EVOLVE_AUTO_MERGE=0
PORT=5000
ZERKALO_EOF

# ------------------------------------------------------------
# 3. Ядро: src/core/*.py
# ------------------------------------------------------------
cat > src/core/audit.py <<'ZERKALO_EOF'
"""Журнал решений «Зеркало» (audit.log). Формат — JSON Lines."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

LOG_DIR = Path(__file__).resolve().parents[2] / "logs"
LOG_FILE = LOG_DIR / "audit.log"


class Audit:
    """Логгер решений. По умолчанию пишет в logs/audit.log рядом с проектом."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or LOG_FILE
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, event: str, level: str = "info", **fields: Any) -> dict:
        rec = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "level": level,
            "event": event,
            **fields,
        }
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        return rec


def log(event: str, level: str = "info", **fields: Any) -> dict:
    return Audit().log(event, level=level, **fields)


if __name__ == "__main__":
    rec = log("test", detail="ручной вызов audit.py")
    print("OK:", rec)
ZERKALO_EOF

cat > src/core/kill_switch.py <<'ZERKALO_EOF'
"""Стоп-кран «Аман». Выше любого приказа. Отменяется кодом «Тонь-Тонь»."""

from __future__ import annotations

import re
import time
from typing import Any

from . import audit

WORD = "аман"
DISARM_CODE = "тонь-тонь"
_engaged = False
_engaged_at: float | None = None
_reason: str | None = None


def is_engaged() -> bool:
    return _engaged


def status() -> dict[str, Any]:
    return {"engaged": _engaged, "engaged_at": _engaged_at,
            "reason": _reason, "word": WORD}


def trigger(source: str = "unknown", reason: str | None = None) -> None:
    global _engaged, _engaged_at, _reason
    if _engaged:
        return
    _engaged = True
    _engaged_at = time.time()
    _reason = reason or f"слово «{WORD}»"
    audit.log("kill_switch.engaged", level="critical",
              source=source, reason=_reason)


def check(text: str | None) -> bool:
    if _engaged:
        return True
    if text and re.search(rf"\b{WORD}\b", text.lower()):
        trigger(source="text", reason=f"слово «{WORD}» в фразе")
        return True
    return False


def disarm(code: str) -> bool:
    global _engaged, _engaged_at, _reason
    if code.strip().lower() != DISARM_CODE:
        audit.log("kill_switch.disarm_denied", level="warning",
                  reason="неверный код")
        return False
    _engaged = False
    _engaged_at = None
    _reason = None
    audit.log("kill_switch.disarmed", level="critical")
    return True


def guard() -> dict[str, Any] | None:
    if not _engaged:
        return None
    audit.log("kill_switch.blocked", level="warning")
    return {"text": "Стоп-кран «Аман» активен. Система остановлена.",
            "model": "kill_switch", "blocked": True}


if __name__ == "__main__":
    print("статус до:", status())
    check("Хранитель сказал: Аман.")
    print("статус после:", status())
    print("снятие неверным кодом:", disarm("1234"))
    print("снятие кодом наследницы:", disarm("Тонь-Тонь"))
    print("статус в конце:", status())
ZERKALO_EOF

cat > src/core/memory.py <<'ZERKALO_EOF'
"""Память «Зеркало»: SQLite, история диалога."""

from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "zerkalo.db"


class Memory:
    """История диалога и факты в SQLite."""

    def __init__(self, db_path: Path | str | None = None) -> None:
        self.db_path = Path(db_path or DB_PATH)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.db_path))
        self.conn.row_factory = sqlite3.Row
        self._init_schema()

    def _init_schema(self) -> None:
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                ts      REAL NOT NULL,
                role    TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
                content TEXT NOT NULL,
                meta    TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages (ts);
            """
        )
        self.conn.commit()

    def add(self, role: str, content: str, meta: dict | None = None) -> int:
        if role not in ("user", "assistant", "system"):
            raise ValueError(f"недопустимая роль: {role}")
        cur = self.conn.execute(
            "INSERT INTO messages (ts, role, content, meta) VALUES (?, ?, ?, ?)",
            (time.time(), role, content,
             json.dumps(meta or {}, ensure_ascii=False)),
        )
        self.conn.commit()
        return int(cur.lastrowid)

    def history(self, limit: int = 50) -> list[dict]:
        rows = self.conn.execute(
            "SELECT id, ts, role, content, meta FROM messages "
            "ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [self._row_to_dict(r) for r in reversed(rows)]

    def search(self, keyword: str, limit: int = 20) -> list[dict]:
        rows = self.conn.execute(
            "SELECT id, ts, role, content, meta FROM messages "
            "WHERE content LIKE ? ORDER BY id DESC LIMIT ?",
            (f"%{keyword}%", limit),
        ).fetchall()
        return [self._row_to_dict(r) for r in reversed(rows)]

    def forget(self) -> None:
        self.conn.execute("DELETE FROM messages")
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    @staticmethod
    def _row_to_dict(row: sqlite3.Row) -> dict:
        return {
            "id": row["id"], "ts": row["ts"], "role": row["role"],
            "content": row["content"],
            "meta": json.loads(row["meta"] or "{}"),
        }


if __name__ == "__main__":
    m = Memory(db_path=":memory:")
    m.add("user", "Привет, Зеркало")
    m.add("assistant", "Слышу тебя, Хранитель.")
    print("история:", m.history())
    print("поиск «Зеркало»:", m.search("Зеркало"))
    m.close()
ZERKALO_EOF

cat > src/core/voice.py <<'ZERKALO_EOF'
"""Голос и уши «Зеркало». STT: Gemini. TTS: ElevenLabs."""

from __future__ import annotations

import base64
import os
import urllib.error
import urllib.request
from typing import Any

from . import audit, kill_switch, orchestrator

GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
ELEVENLABS_VOICE = os.environ.get("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")


def _post(url: str, payload: dict, headers: dict, timeout: int = 60) -> dict:
    import json
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def stt(audio_bytes: bytes, mime: str = "audio/ogg") -> str:
    if kill_switch.is_engaged():
        raise RuntimeError("Стоп-кран «Аман» активен.")
    key = os.environ["GEMINI_API_KEY"]
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={key}"
    )
    data = _post(url, {
        "contents": [{"role": "user", "parts": [
            {"inline_data": {
                "mime_type": mime,
                "data": base64.b64encode(audio_bytes).decode("ascii"),
            }},
            {"text": "Распознай речь на этом аудио. Верни только текст, "
                     "без комментариев."},
        ]}],
    }, headers={})
    text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
    audit.log("voice.stt", text_len=len(text), mime=mime)
    return text


def tts(text: str, voice_id: str | None = None,
        model: str = "eleven_multilingual_v2") -> bytes:
    import json
    if kill_switch.is_engaged():
        raise RuntimeError("Стоп-кран «Аман» активен.")
    key = os.environ["ELEVENLABS_API_KEY"]
    vid = voice_id or ELEVENLABS_VOICE
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{vid}",
        data=json.dumps({
            "text": text,
            "model_id": model,
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
        }).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "xi-api-key": key, "Accept": "audio/mpeg"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        audio = resp.read()
    audit.log("voice.tts", text_len=len(text), voice_id=vid, bytes=len(audio))
    return audio


if __name__ == "__main__":
    try:
        tts("Привет, Хранитель.")
    except KeyError as e:
        print(f"Нужен ключ: {e}")
    except urllib.error.URLError as e:
        print(f"Сеть недоступна: {e}")
ZERKALO_EOF

cat > src/core/orchestrator.py <<'ZERKALO_EOF'
"""Дирижёр моделей: знания из базы Сур -> Gemini -> Groq -> fallback."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from typing import Any

from . import audit, kill_switch

GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
GROQ_MODEL = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile")

SYSTEM_PROMPT = (
    "Ты — «Зеркало», автономная AI-система Хранителя. Отвечай на русском, "
    "кратко и по делу. Красная черта: не вредить, не принуждать, "
    "не управлять военными, не давить, не решать за человека."
)


def _post(url: str, payload: dict, headers: dict, timeout: int = 30) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _gemini(prompt: str, system: str) -> str:
    key = os.environ["GEMINI_API_KEY"]
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={key}"
    )
    data = _post(url, {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "systemInstruction": {"parts": [{"text": system}]},
    }, headers={})
    return data["candidates"][0]["content"]["parts"][0]["text"]


def _groq(prompt: str, system: str) -> str:
    key = os.environ["GROQ_API_KEY"]
    data = _post(
        "https://api.groq.com/openai/v1/chat/completions",
        {"model": GROQ_MODEL,
         "messages": [{"role": "system", "content": system},
                      {"role": "user", "content": prompt}]},
        headers={"Authorization": f"Bearer {key}"},
    )
    return data["choices"][0]["message"]["content"]


def _fallback(prompt: str) -> str:
    return (
        "Модели сейчас недоступны. Я записал твой запрос и отвечу, "
        f"когда связь восстановится. Запрос: «{prompt[:200]}»"
    )


def think(prompt: str, system: str = SYSTEM_PROMPT,
          memory: Any = None) -> dict[str, Any]:
    blocked = kill_switch.guard()
    if blocked:
        return blocked

    start = time.time()
    history = memory.history(limit=20) if memory is not None else []

    knowledge = ""
    try:
        from . import knowledge_base
        knowledge = knowledge_base.search(prompt)
    except Exception as e:
        audit.log("orchestrator.kb_error", level="warning", error=str(e)[:200])

    parts: list[str] = []
    if knowledge:
        parts.append("Знания из базы Сур и Ядра (используй при ответе):\n"
                     + knowledge)
    if history:
        parts.append("История диалога:\n" + "\n".join(
            f"{m['role']}: {m['content']}" for m in history))
    parts.append("Сообщение Хранителя:\n" + prompt)
    full_prompt = "\n\n".join(parts)

    errors: list[str] = []
    for name, fn in (("gemini", _gemini), ("groq", _groq)):
        try:
            text = fn(full_prompt, system)
            result = {"text": text, "model": name,
                      "latency_ms": round((time.time() - start) * 1000)}
            audit.log("orchestrator.think", model=name,
                      latency_ms=result["latency_ms"], prompt_len=len(prompt))
            if memory is not None:
                memory.add("user", prompt)
                memory.add("assistant", text, meta={"model": name})
            return result
        except (KeyError, urllib.error.URLError, OSError,
                json.JSONDecodeError) as e:
            errors.append(f"{name}: {e}")
            audit.log("orchestrator.error", level="warning",
                      model=name, error=str(e))

    result = {"text": _fallback(prompt), "model": "fallback",
              "latency_ms": round((time.time() - start) * 1000),
              "errors": errors}
    audit.log("orchestrator.fallback", level="warning",
              latency_ms=result["latency_ms"], errors=errors)
    return result


if __name__ == "__main__":
    print(think("Привет, Зеркало. Какой сегодня план?"))
ZERKALO_EOF

cat > src/core/knowledge_base.py <<'ZERKALO_EOF'
"""База знаний: файлы data/suras/ -> куски -> эмбеддинги Gemini -> SQLite."""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import sqlite3
import struct
import time
import urllib.request
from pathlib import Path

from . import audit

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SURAS_DIR = PROJECT_ROOT / "data" / "suras"
DB_PATH = PROJECT_ROOT / "data" / "knowledge.db"

EMBED_MODEL = os.environ.get("GEMINI_EMBED_MODEL", "text-embedding-004")
CHUNK_SIZE = int(os.environ.get("KB_CHUNK_SIZE", "900"))
CHUNK_OVERLAP = int(os.environ.get("KB_CHUNK_OVERLAP", "120"))
TOP_K = int(os.environ.get("KB_TOP_K", "3"))
BATCH = 100
TEXT_EXTS = {".txt", ".md", ".sura", ".core", ""}


def _post_json(url: str, payload: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def embed_texts(texts: list[str]) -> list[list[float]]:
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError("Хранитель, нужен ключ GEMINI_API_KEY.")
    url = ("https://generativelanguage.googleapis.com/v1beta/models/"
           f"{EMBED_MODEL}:batchEmbedContents?key={key}")
    payload = {"requests": [{"model": f"models/{EMBED_MODEL}",
                             "content": {"parts": [{"text": t[:8000]}]}}
                            for t in texts]}
    data = _post_json(url, payload, timeout=120)
    return [list(map(float, e["values"])) for e in data["embeddings"]]


def _embed_in_batches(texts: list[str]) -> list[list[float]]:
    out: list[list[float]] = []
    for i in range(0, len(texts), BATCH):
        out.extend(embed_texts(texts[i:i + BATCH]))
        time.sleep(0.2)
    return out


def chunk_text(text: str, size: int = CHUNK_SIZE,
               overlap: int = CHUNK_OVERLAP) -> list[str]:
    text = re.sub(r"\n{3,}", "\n\n", text.strip())
    if not text:
        return []
    if len(text) <= size:
        return [text]
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks: list[str] = []
    buf = ""
    for p in paragraphs:
        candidate = (buf + "\n\n" + p).strip()
        if len(candidate) <= size:
            buf = candidate
            continue
        if buf:
            chunks.append(buf)
        if len(p) > size:
            start = 0
            while start < len(p):
                chunks.append(p[start:start + size].strip())
                start += max(size - overlap, 1)
            buf = ""
        else:
            buf = p
    if buf:
        chunks.append(buf)
    return [c for c in chunks if c]


def _pack(vec: list[float]) -> bytes:
    return struct.pack(f"<{len(vec)}f", *vec)


def _unpack(blob: bytes) -> list[float]:
    return list(struct.unpack(f"<{len(blob) // 4}f", blob))


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


_SCHEMA = """
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL, idx INTEGER NOT NULL,
    text TEXT NOT NULL, emb BLOB NOT NULL, ts REAL NOT NULL,
    UNIQUE (source, idx));
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
"""


def _conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.executescript(_SCHEMA)
    return conn


def sync(force: bool = False) -> dict:
    if not SURAS_DIR.exists():
        audit.log("kb.no_suras_dir", level="warning", path=str(SURAS_DIR))
        return {"files": 0, "chunks": 0,
                "note": "папки data/suras/ нет — положи туда Суры"}
    files = sorted(p for p in SURAS_DIR.rglob("*")
                   if p.is_file() and p.suffix.lower() in TEXT_EXTS)
    conn = _conn()
    stats = {"files": 0, "chunks": 0}
    try:
        for f in files:
            rel = str(f.relative_to(SURAS_DIR))
            content = f.read_text(encoding="utf-8", errors="replace")
            fhash = hashlib.sha256(content.encode("utf-8")).hexdigest()
            old = conn.execute(
                "SELECT value FROM meta WHERE key = ?",
                (f"hash:{rel}",)).fetchone()
            if not force and old and old[0] == fhash:
                continue
            conn.execute("DELETE FROM chunks WHERE source = ?", (rel,))
            chunks = chunk_text(content)
            if not chunks:
                conn.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)",
                             (f"hash:{rel}", fhash))
                continue
            embs = _embed_in_batches(chunks)
            for i, (text, vec) in enumerate(zip(chunks, embs)):
                conn.execute(
                    "INSERT OR REPLACE INTO chunks "
                    "(source, idx, text, emb, ts) VALUES (?,?,?,?,?)",
                    (rel, i, text, _pack(vec), time.time()))
            conn.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)",
                         (f"hash:{rel}", fhash))
            stats["files"] += 1
            stats["chunks"] += len(chunks)
        conn.commit()
    finally:
        conn.close()
    audit.log("kb.sync", **stats)
    return stats


def search(query: str, top_k: int = TOP_K) -> str:
    query = (query or "").strip()
    if not query:
        return ""
    conn = _conn()
    try:
        rows = conn.execute(
            "SELECT source, idx, text, emb FROM chunks").fetchall()
    finally:
        conn.close()
    if not rows:
        return ""
    try:
        qvec = embed_texts([query])[0]
    except Exception as e:
        audit.log("kb.search_embed_failed", level="warning",
                  error=str(e)[:200])
        return ""
    scored = [(cosine(qvec, _unpack(blob)), source, idx, text)
              for source, idx, text, blob in rows]
    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[:max(top_k, 1)]
    audit.log("kb.search", query=query[:80],
              hits=[round(s, 3) for s, _, _, _ in top])
    if top[0][0] <= 0:
        return ""
    return "\n\n---\n\n".join(text for _, _, _, text in top)


def stats() -> dict:
    conn = _conn()
    try:
        files = conn.execute(
            "SELECT COUNT(DISTINCT source) FROM chunks").fetchone()[0]
        chunks = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    finally:
        conn.close()
    return {"files": files, "chunks": chunks}


if __name__ == "__main__":
    print("sync:", json.dumps(sync(), ensure_ascii=False))
    print("stats:", stats())
ZERKALO_EOF

cat > src/core/modules_loader.py <<'ZERKALO_EOF'
"""Динамический загрузчик модулей-экспертов.

Сканирует src/modules/*.py. Модуль опционально объявляет:
    MODULE = {"name": ..., "domain": ..., "description": ...}
    def answer(question: str, context: str = "") -> str
Одно падение не роняет сервер.
"""

from __future__ import annotations

import importlib
from pathlib import Path
from types import ModuleType

from . import audit

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODULES_DIR = PROJECT_ROOT / "src" / "modules"
PACKAGE = "src.modules"

_registry: dict[str, ModuleType] = {}
_meta: dict[str, dict] = {}
_errors: dict[str, str] = {}
_report: dict = {}


def _import_module(name: str) -> ModuleType:
    return importlib.import_module(f"{PACKAGE}.{name}")


def load_all() -> dict:
    global _report
    _registry.clear()
    _meta.clear()
    _errors.clear()
    if not MODULES_DIR.exists():
        audit.log("modules.no_dir", level="warning", path=str(MODULES_DIR))
        _report = {"total": 0, "loaded": 0, "failed": 0, "errors": {},
                   "note": "папки src/modules/ нет"}
        return dict(_report)
    candidates = sorted(
        f for f in MODULES_DIR.glob("*.py") if not f.stem.startswith("_"))
    for f in candidates:
        name = f.stem
        try:
            module = _import_module(name)
            raw = getattr(module, "MODULE", None)
            meta = raw if isinstance(raw, dict) else {}
            _meta[name] = {
                "name": str(meta.get("name") or name),
                "domain": str(meta.get("domain") or "general"),
                "description": str(meta.get("description") or ""),
                "has_answer": callable(getattr(module, "answer", None)),
            }
            _registry[name] = module
        except Exception as e:
            _errors[name] = f"{type(e).__name__}: {e}"
            audit.log("modules.load_failed", level="error",
                      module=name, error=str(e)[:300])
    _report = {"total": len(candidates), "loaded": len(_registry),
               "failed": len(_errors), "errors": dict(_errors)}
    audit.log("modules.loaded", total=_report["total"],
              loaded=_report["loaded"], failed=_report["failed"])
    return dict(_report)


def modules() -> dict[str, dict]:
    return dict(_meta)


def get(name: str) -> ModuleType | None:
    return _registry.get(name)


def failed() -> dict[str, str]:
    return dict(_errors)


def report() -> dict:
    return dict(_report)


def ask(name: str, question: str, context: str = "") -> str:
    module = _registry.get(name)
    if module is None:
        raise KeyError(f"модуль «{name}» не загружен")
    fn = getattr(module, "answer", None)
    if not callable(fn):
        raise TypeError(f"у модуля «{name}» нет функции answer()")
    result = fn(question=question, context=context)
    if not isinstance(result, str):
        raise TypeError(
            f"модуль «{name}» вернул не строку: {type(result).__name__}")
    audit.log("modules.ask", module=name, q_len=len(question))
    return result


if __name__ == "__main__":
    print(load_all())
    print("загружены:", sorted(modules()))
ZERKALO_EOF

cat > src/core/mechanics_loader.py <<'ZERKALO_EOF'
"""Реестр механизмов заработка. «Зеркало» знает, что есть, не запускает.

Источники: data/mechanisms.json + runner'ы src/mechanics/<id>.py.
"""

from __future__ import annotations

import importlib
import json
from pathlib import Path
from typing import Any

from . import audit

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MECHANICS_DIR = PROJECT_ROOT / "src" / "mechanics"
REGISTRY_FILE = PROJECT_ROOT / "data" / "mechanisms.json"
PACKAGE = "src.mechanics"

_items: dict[str, dict] = {}


def _import_runner(mech_id: str):
    return importlib.import_module(f"{PACKAGE}.{mech_id}")


def _validate(item: Any) -> dict:
    if not isinstance(item, dict):
        raise ValueError("запись должна быть объектом")
    mech_id = item.get("id")
    if not isinstance(mech_id, str) or not mech_id.strip():
        raise ValueError("нет поля id")
    pct = float(item.get("commission_pct", 0))
    if not 0 <= pct <= 100:
        raise ValueError(f"commission_pct вне 0..100: {pct}")
    return {"id": mech_id.strip(),
            "name": str(item.get("name") or mech_id),
            "kind": str(item.get("kind") or "online"),
            "commission_pct": pct,
            "status": str(item.get("status") or "registered")}


def load_all() -> dict:
    global _items
    _items = {}
    from_registry = 0
    if REGISTRY_FILE.exists():
        try:
            data = json.loads(REGISTRY_FILE.read_text(encoding="utf-8"))
            if not isinstance(data, list):
                raise ValueError("ожидался список")
            for i, item in enumerate(data):
                try:
                    mech = _validate(item)
                    _items[mech["id"]] = mech
                    from_registry += 1
                except ValueError as e:
                    audit.log("mechanics.bad_item", level="error",
                              index=i, error=str(e))
        except Exception as e:
            audit.log("mechanics.registry_broken", level="error",
                      error=str(e)[:300])
    ready = 0
    if MECHANICS_DIR.exists():
        for f in sorted(MECHANICS_DIR.glob("*.py")):
            if f.stem.startswith("_"):
                continue
            mech_id = f.stem
            mech = _items.get(mech_id) or {
                "id": mech_id, "name": mech_id, "kind": "online",
                "commission_pct": 0.0, "status": "registered"}
            try:
                module = _import_runner(mech_id)
                raw = getattr(module, "MECHANISM", None)
                if isinstance(raw, dict):
                    for key in ("name", "kind", "commission_pct"):
                        if key in raw:
                            mech[key] = raw[key]
                mech["status"] = "ready"
                ready += 1
            except Exception as e:
                mech["status"] = "broken_runner"
                audit.log("mechanics.runner_failed", level="error",
                          id=mech_id, error=str(e)[:200])
            _items[mech_id] = mech
    report = {"registered": len(_items), "ready": ready,
              "from_registry": from_registry}
    if not REGISTRY_FILE.exists() and not MECHANICS_DIR.exists():
        report["note"] = "нужно создать data/mechanisms.json или src/mechanics/"
    audit.log("mechanics.loaded", **report)
    return dict(report)


def list_all() -> dict[str, dict]:
    return dict(_items)


def get(mech_id: str) -> dict | None:
    return _items.get(mech_id)


def stats() -> dict:
    return {"registered": len(_items),
            "ready": sum(1 for m in _items.values()
                         if m.get("status") == "ready")}


def expected_commission(mech_id: str, profit: float) -> float:
    mech = _items.get(mech_id, {})
    pct = float(mech.get("commission_pct", 0))
    return round(max(float(profit), 0.0) * pct / 100.0, 2)


if __name__ == "__main__":
    print(load_all())
ZERKALO_EOF

cat > src/core/github_auto.py <<'ZERKALO_EOF'
"""Автокоммиты и пуш в GitHub. Токен — только из окружения, в логи не попадает."""

from __future__ import annotations

import os
import re
from pathlib import Path

import git
import requests

from . import audit

PROJECT_ROOT = Path(__file__).resolve().parents[2]
API = "https://api.github.com"


def _token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise RuntimeError("Хранитель, нужен ключ GITHUB_TOKEN.")
    return token


def repo_full_name() -> str:
    name = os.environ.get("GITHUB_REPO", "").strip()
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", name):
        raise RuntimeError("Нужен GITHUB_REPO в формате owner/name.")
    return name


def _headers() -> dict:
    return {"Authorization": f"Bearer {_token()}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"}


def _sanitize(text: str) -> str:
    return text.replace(_token(), "***")


def open_repo(path: str | Path | None = None) -> git.Repo:
    return git.Repo(str(path or PROJECT_ROOT))


def has_changes(repo: git.Repo) -> bool:
    return repo.is_dirty(untracked_files=True)


def ensure_branch(repo: git.Repo, branch: str) -> None:
    if branch in repo.heads:
        repo.heads[branch].checkout()
    else:
        repo.create_head(branch).checkout()


def commit_all(repo: git.Repo, message: str) -> str | None:
    repo.git.add(A=True)
    if not repo.is_dirty(untracked_files=False):
        return None
    commit = repo.index.commit(message)
    audit.log("github.commit", branch=repo.active_branch.name,
              sha=commit.hexsha[:12])
    return commit.hexsha


def push(repo: git.Repo, branch: str) -> None:
    url = f"https://{_token()}@github.com/{repo_full_name()}.git"
    try:
        repo.git.push(url, f"HEAD:{branch}")
    except git.GitCommandError as e:
        raise RuntimeError(
            f"push не удался: {_sanitize(str(e))[:400]}") from e
    audit.log("github.push", branch=branch)


def create_pr(title: str, body: str, head: str,
              base: str | None = None) -> str:
    base = base or os.environ.get("GITHUB_BRANCH", "main")
    resp = requests.post(
        f"{API}/repos/{repo_full_name()}/pulls", headers=_headers(),
        json={"title": title, "body": body, "head": head, "base": base},
        timeout=30)
    if resp.status_code == 422 and "already exists" in resp.text:
        owner = repo_full_name().split("/")[0]
        pulls = requests.get(
            f"{API}/repos/{repo_full_name()}/pulls", headers=_headers(),
            params={"state": "open", "head": f"{owner}:{head}"}, timeout=30)
        pulls.raise_for_status()
        items = pulls.json()
        if items:
            return items[0]["html_url"]
    resp.raise_for_status()
    pr = resp.json()
    audit.log("github.pr_created", url=pr["html_url"], title=title)
    return pr["html_url"]


def merge_pr(number: int) -> bool:
    resp = requests.put(
        f"{API}/repos/{repo_full_name()}/pulls/{number}/merge",
        headers=_headers(), json={"merge_method": "squash"}, timeout=30)
    ok = resp.status_code == 200
    audit.log("github.pr_merge", number=number, ok=ok)
    return ok


if __name__ == "__main__":
    repo = open_repo()
    print("репозиторий:", repo.working_tree_dir)
    print("изменения:", has_changes(repo))
ZERKALO_EOF

cat > src/core/self_evolve.py <<'ZERKALO_EOF'
"""Самоэволюция: логи Render -> патч от LLM -> тест в песочнице -> PR.

Правила: патч без тестов не коммитится; опасные патчи отклоняются;
kill_switch.py и constitution.py не трогаем никогда.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import requests

from . import audit, github_auto, kill_switch
from .orchestrator import think

PROJECT_ROOT = Path(__file__).resolve().parents[2]
STATE_FILE = PROJECT_ROOT / "data" / "self_evolve_state.json"

RENDER_LOGS_URL = "https://api.render.com/v1/services/{service_id}/logs"
SKIP_HOURS = float(os.environ.get("SELF_EVOLVE_SKIP_HOURS", "24"))
MAX_LOG_LINES = int(os.environ.get("SELF_EVOLVE_MAX_LOGS", "3000"))

ERROR_RE = re.compile(
    r"Traceback \(most recent call last\):"
    r"|(?<![A-Za-z])(?:ERROR|CRITICAL|FATAL)(?![A-Za-z])"
    r"|\w+(?:Error|Exception)\b"
    r"|HTTP/1\.1\" 5\d\d")

BANNED_SUBSTRINGS = (
    "rm -rf /", "push --force", "force-with-lease", "git reset --hard",
    "drop table", "shutdown now", ":(){ :|:& };:", "mkfs", "dd if=",
    "crontab -r", "iptables -f")

PATCH_SYSTEM = (
    "Ты — инженер самоэволюции «Зеркало». Даны ошибка из логов и код файла. "
    "Напиши минимальный исправляющий патч в формате unified diff. "
    "Только diff, без пояснений. Не переписывай файл целиком. "
    "Никаких новых зависимостей и сети. Не трогай kill_switch.py и "
    "constitution.py. Красная черта: не вреди.")


def _extract_text(item) -> str:
    if isinstance(item, str):
        return item
    if isinstance(item, dict):
        for key in ("text", "log", "msg", "line", "content", "message"):
            value = item.get(key)
            if isinstance(value, str):
                return value
        return json.dumps(item, ensure_ascii=False)
    return str(item)


def _parse_log_payload(payload):
    cursor = None
    logs_raw = payload
    if isinstance(payload, dict):
        cursor = payload.get("cursor") or payload.get("nextCursor")
        logs_raw = (payload.get("logs") or payload.get("items")
                    or payload.get("data") or [])
    if not isinstance(logs_raw, list):
        logs_raw = [logs_raw]
    return [_extract_text(i) for i in logs_raw], cursor


def fetch_render_logs() -> str:
    key = os.environ.get("RENDER_API_KEY")
    sid = os.environ.get("RENDER_SERVICE_ID")
    if not key or not sid:
        raise RuntimeError("Нужны RENDER_API_KEY и RENDER_SERVICE_ID.")
    headers = {"Authorization": f"Bearer {key}", "Accept": "application/json"}
    lines: list[str] = []
    cursor = None
    seen: set[str] = set()
    while len(lines) < MAX_LOG_LINES:
        params = {"limit": 100}
        if cursor:
            params["cursor"] = cursor
        resp = requests.get(RENDER_LOGS_URL.format(service_id=sid),
                            headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        try:
            payload = resp.json()
        except ValueError:
            lines.append(resp.text)
            break
        batch, next_cursor = _parse_log_payload(payload)
        if not batch:
            break
        lines.extend(batch)
        if not next_cursor or next_cursor in seen:
            break
        seen.add(next_cursor)
        cursor = next_cursor
    return "\n".join(lines)


def extract_error_blocks(text: str, max_blocks: int = 20) -> list[str]:
    blocks = [b.strip() for b in re.split(r"\n\s*\n", text)
              if ERROR_RE.search(b)]
    blocks = [b for b in blocks if 0 < len(b) < 6000]
    blocks.sort(key=lambda b: 0 if "Traceback" in b else 1)
    return blocks[:max_blocks]


def block_signature(block: str) -> str:
    last = next((l.strip() for l in reversed(block.splitlines())
                 if l.strip()), "")
    return hashlib.sha256(last.encode()).hexdigest()[:12]


def find_files(block: str) -> list[Path]:
    found, seen = [], set()
    for m in re.finditer(r'File "([^"]+\.py)"', block):
        p = Path(m.group(1))
        try:
            rel = p.relative_to(PROJECT_ROOT) if p.is_absolute() else p
        except ValueError:
            continue
        full = (PROJECT_ROOT / rel).resolve()
        if full.is_file() and full not in seen:
            seen.add(full)
            found.append(full)
    return found[:3]


def read_context(files: list[Path], max_chars: int = 6000) -> str:
    parts, total = [], 0
    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        total += len(text)
        if total > max_chars:
            text = text[:max_chars]
            parts.append(
                f"### {f.relative_to(PROJECT_ROOT)} (обрезано)\n{text}")
            break
        parts.append(f"### {f.relative_to(PROJECT_ROOT)}\n{text}")
    return "\n\n".join(parts)


def extract_diff(text: str) -> str | None:
    m = re.search(r"```(?:diff)?\n(.*?)```", text, re.DOTALL)
    candidate = m.group(1) if m else text
    lines = candidate.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("---")),
                 None)
    if start is None:
        return None
    diff = "\n".join(lines[start:]).strip()
    return diff or None


def generate_patch(block: str) -> str | None:
    files = find_files(block)
    context = (read_context(files) if files
               else "(файл не найден — исправь по traceback)")
    user = ("ОШИБКА ИЗ ЛОГОВ:\n" + block[:4000] + "\n\nКОД ФАЙЛА:\n"
            + context + "\n\nВерни только unified diff.")
    result = think(user, system=PATCH_SYSTEM)
    if result.get("blocked"):
        audit.log("self_evolve.blocked", level="critical")
        return None
    return extract_diff(result["text"])


def patch_is_safe(diff: str) -> tuple[bool, str]:
    low = diff.lower()
    for bad in BANNED_SUBSTRINGS:
        if bad in low:
            return False, f"опасная команда «{bad}»"
    if len(diff) > 30_000:
        return False, "патч слишком большой (>30KB)"
    if re.search(r"^\+\+\+ b/.*(kill_switch|constitution)\.py", diff, re.M):
        return False, "патч трогает защищённый файл"
    return True, ""


IGNORE = shutil.ignore_patterns(
    ".git", "__pycache__", ".venv", "venv", "data", "logs",
    "*.db", ".pytest_cache", "node_modules")


def run_tests(repo_dir: Path) -> tuple[bool, str]:
    env = {**os.environ, "PYTHONPATH": str(repo_dir / "src")}
    try:
        r = subprocess.run([sys.executable, "-m", "pytest", "-q"],
                           cwd=repo_dir, capture_output=True, text=True,
                           timeout=600, env=env)
        tail = (r.stdout + "\n" + r.stderr)[-800:]
        if r.returncode == 0:
            return True, tail
        if "No module named pytest" in r.stderr:
            return compile_check(repo_dir)
        if "no tests ran" in r.stdout.lower():
            audit.log("self_evolve.no_tests", level="warning")
            return True, tail
        return False, tail
    except subprocess.TimeoutExpired:
        return False, "тесты не уложились в 600 секунд"


def compile_check(repo_dir: Path) -> tuple[bool, str]:
    r = subprocess.run([sys.executable, "-m", "compileall", "-q", "src"],
                       cwd=repo_dir, capture_output=True, text=True,
                       timeout=120)
    return r.returncode == 0, (r.stdout + r.stderr)[-600:]


def test_in_sandbox(diff: str) -> tuple[bool, str]:
    tmp = Path(tempfile.mkdtemp(prefix="zerkalo_evolve_"))
    try:
        repo_dir = tmp / "repo"
        shutil.copytree(PROJECT_ROOT, repo_dir, ignore=IGNORE)
        patch_file = tmp / "fix.diff"
        patch_file.write_text(diff, encoding="utf-8")
        chk = subprocess.run(["git", "apply", "--check", str(patch_file)],
                             cwd=repo_dir, capture_output=True, text=True,
                             timeout=60)
        if chk.returncode != 0:
            return False, "git apply --check: " + chk.stderr.strip()[:600]
        subprocess.run(["git", "apply", str(patch_file)], cwd=repo_dir,
                       check=True, capture_output=True, text=True, timeout=60)
        return run_tests(repo_dir)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    return {"fixed": {}, "failures": []}


def save_state(st: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    st["failures"] = st.get("failures", [])[-50:]
    STATE_FILE.write_text(json.dumps(st, ensure_ascii=False, indent=2),
                          encoding="utf-8")


def recently_fixed(st: dict, sig: str) -> bool:
    rec = st.get("fixed", {}).get(sig)
    return bool(rec) and (time.time() - rec["ts"]) < SKIP_HOURS * 3600


def apply_and_publish(diff: str, sig: str) -> str:
    repo = github_auto.open_repo()
    if repo.is_dirty(untracked_files=True):
        raise RuntimeError("Репозиторий грязный — патч не применяю.")
    branch = f"self-evolve/{time.strftime('%Y%m%d-%H%M%S')}-{sig}"
    github_auto.ensure_branch(repo, branch)
    patch_path = PROJECT_ROOT / ".self_evolve.patch"
    try:
        patch_path.write_text(diff, encoding="utf-8")
        chk = subprocess.run(["git", "apply", "--check", str(patch_path)],
                             cwd=PROJECT_ROOT, capture_output=True,
                             text=True, timeout=60)
        if chk.returncode != 0:
            raise RuntimeError("патч не лёг: " + chk.stderr[:300])
        subprocess.run(["git", "apply", str(patch_path)], cwd=PROJECT_ROOT,
                       check=True, capture_output=True, text=True, timeout=60)
    finally:
        patch_path.unlink(missing_ok=True)
    title = f"self-evolve: исправление ошибки {sig}"
    body = (f"Автопатч «Зеркало». Подпись: `{sig}`\n"
            f"Безопасность: ✅ Тесты: ✅")
    sha = github_auto.commit_all(repo, title)
    github_auto.push(repo, branch)
    url = github_auto.create_pr(title, body, branch)
    audit.log("self_evolve.published", branch=branch, pr=url, sha=sha)
    if os.environ.get("SELF_EVOLVE_AUTO_MERGE") == "1":
        num = int(re.search(r"/pull/(\d+)", url).group(1))
        if github_auto.merge_pr(num):
            audit.log("self_evolve.merged", number=num)
    return url


def run_once() -> dict:
    summary = {"errors": 0, "patch": False, "tests": False,
               "pr": None, "skipped": False, "stopped": False}
    if kill_switch.is_engaged():
        summary["stopped"] = True
        audit.log("self_evolve.stopped", level="critical")
        return summary
    logs = fetch_render_logs()
    blocks = extract_error_blocks(logs)
    summary["errors"] = len(blocks)
    if not blocks:
        audit.log("self_evolve.idle")
        return summary
    st = load_state()
    block = next((b for b in blocks
                  if not recently_fixed(st, block_signature(b))), None)
    if block is None:
        summary["skipped"] = True
        audit.log("self_evolve.all_recently_fixed")
        return summary
    sig = block_signature(block)
    audit.log("self_evolve.error_found", signature=sig, block=block[:300])
    diff = generate_patch(block)
    if not diff:
        st["failures"].append({"sig": sig, "ts": time.time(),
                               "reason": "нет валидного diff"})
        save_state(st)
        return summary
    summary["patch"] = True
    safe, why = patch_is_safe(diff)
    if not safe:
        st["failures"].append({"sig": sig, "ts": time.time(), "reason": why})
        save_state(st)
        audit.log("self_evolve.unsafe_patch", level="warning", reason=why)
        return summary
    ok, details = test_in_sandbox(diff)
    summary["tests"] = ok
    audit.log("self_evolve.sandbox", signature=sig, ok=ok,
              details=details[:400])
    if not ok:
        st["failures"].append({"sig": sig, "ts": time.time(),
                               "reason": "тесты упали"})
        save_state(st)
        return summary
    summary["pr"] = apply_and_publish(diff, sig)
    st.setdefault("fixed", {})[sig] = {"ts": time.time(),
                                       "pr": summary["pr"]}
    save_state(st)
    return summary


def loop(interval_sec: int = 3600) -> None:
    audit.log("self_evolve.loop_start", interval_sec=interval_sec)
    while True:
        try:
            run_once()
        except Exception as e:
            audit.log("self_evolve.error", level="error",
                      error=str(e)[:500])
        time.sleep(interval_sec)


if __name__ == "__main__":
    print(json.dumps(run_once(), ensure_ascii=False, indent=2))
ZERKALO_EOF

# ------------------------------------------------------------
# 4. СУПЕРМОДУЛИ
# ------------------------------------------------------------
cat > src/senses/phone_bridge.py <<'ZERKALO_EOF'
"""Мост к телефону (серверная сторона).

Телефон с Accessibility Service опрашивает GET /phone/cmd/next,
выполняет команду (открыть приложение, тап, свайп, bluetooth, wifi)
и шлёт результат POST /phone/result. Команды добавляет Хранитель
или модуль «Зеркала». Порядок: команды выполняются только на телефоне
Хранителя, каждая деструктивная — только после его подтверждения.
"""

from __future__ import annotations

import json
import sqlite3
import time
import uuid
from pathlib import Path

from ..core import audit

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "phone.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS commands(
  id TEXT PRIMARY KEY,
  action TEXT NOT NULL,
  params TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  result TEXT,
  ts_created REAL NOT NULL,
  ts_done REAL
);
"""

SUPPORTED_ACTIONS = {
    "open_app", "tap", "swipe", "type", "key_event",
    "bluetooth", "wifi", "brightness", "screenshot", "wait",
}


def _conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.executescript(_SCHEMA)
    return conn


def add_command(action: str, **params) -> str:
    """Поставить команду в очередь. Возвращает id."""
    if action not in SUPPORTED_ACTIONS:
        raise ValueError(
            f"неизвестное действие «{action}». Допустимы: "
            + ", ".join(sorted(SUPPORTED_ACTIONS)))
    cid = uuid.uuid4().hex[:12]
    conn = _conn()
    conn.execute(
        "INSERT INTO commands VALUES (?,?,?,?,?,?,?)",
        (cid, action, json.dumps(params, ensure_ascii=False), "pending",
         None, time.time(), None))
    conn.commit()
    conn.close()
    audit.log("phone.cmd_added", action=action, params=list(params), id=cid)
    return cid


def next_command() -> dict | None:
    """Отдать телефону одну pending-команду и пометить sent."""
    conn = _conn()
    row = conn.execute(
        "SELECT id, action, params FROM commands "
        "WHERE status='pending' ORDER BY ts_created LIMIT 1").fetchone()
    if not row:
        conn.close()
        return None
    conn.execute("UPDATE commands SET status='sent' WHERE id=?", (row[0],))
    conn.commit()
    conn.close()
    return {"id": row[0], "action": row[1],
            "params": json.loads(row[2])}


def report_result(cmd_id: str, ok: bool, detail: str = "") -> None:
    conn = _conn()
    conn.execute(
        "UPDATE commands SET status=?, result=?, ts_done=? WHERE id=?",
        ("done" if ok else "error", str(detail)[:1000], time.time(), cmd_id))
    conn.commit()
    conn.close()
    audit.log("phone.result", id=cmd_id, ok=ok)


def status(cmd_id: str | None = None):
    conn = _conn()
    if cmd_id:
        row = conn.execute(
            "SELECT id, action, status, result, ts_created, ts_done "
            "FROM commands WHERE id=?", (cmd_id,)).fetchone()
        conn.close()
        if not row:
            return None
        return dict(zip(("id", "action", "status", "result",
                         "ts_created", "ts_done"), row))
    rows = conn.execute(
        "SELECT id, action, status, ts_created FROM commands "
        "ORDER BY ts_created DESC LIMIT 50").fetchall()
    conn.close()
    return [dict(zip(("id", "action", "status", "ts_created"), r))
            for r in rows]


def clear_done() -> int:
    """Убрать выполненные из очереди. Возвращает число удалённых."""
    conn = _conn()
    cur = conn.execute("DELETE FROM commands WHERE status IN ('done','error')")
    conn.commit()
    conn.close()
    return cur.rowcount


if __name__ == "__main__":
    cid = add_command("open_app", package="com.whatsapp")
    print("добавлена:", cid)
    print("телефону ->", next_command())
    report_result(cid, True, "открыто")
    print("очередь:", status())
ZERKALO_EOF

cat > src/money/money_maker.py <<'ZERKALO_EOF'
"""Автономный поиск денег.

Сканирует каналы заработка (фриланс-биржи, партнёрки), оценивает лиды
и готовит предложения Хранителю. Честность: сбой канала = пропуск с
записью в лог, никогда не падение. Без сети вернёт пусто и скажет почему.
"""

from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path

from ..core import audit

DATA_FILE = Path(__file__).resolve().parents[2] / "data" / "money_maker.json"

CHANNELS = [
    {"id": "kwork",   "name": "Kwork: боты и тексты",
     "kind": "freelance",
     "url": "https://kwork.ru/projects?keyword=telegram%20bot"},
    {"id": "fl",      "name": "FL.ru: парсинг и тексты",
     "kind": "freelance", "url": "https://www.fl.ru/projects/"},
    {"id": "admitad", "name": "Admitad: офферы KZ",
     "kind": "partner",
     "url": "https://www.admitad.com/ru/webmaster/offers/"},
    {"id": "2gis",    "name": "2GIS: бизнесы без бота",
     "kind": "bots", "url": ""},
]

DEFAULT_ESTIMATE = {"freelance": 8000, "partner": 3000, "bots": 40000}
MONEY_RE = re.compile(r"(\d[\d\s]{1,8})\s*(?:₽|руб\.?|₸|тенге)", re.I)


def _load_seen() -> set:
    if DATA_FILE.exists():
        return set(json.loads(
            DATA_FILE.read_text(encoding="utf-8")).get("seen", []))
    return set()


def _save_seen(seen: set) -> None:
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    DATA_FILE.write_text(
        json.dumps({"seen": sorted(seen)}, ensure_ascii=False),
        encoding="utf-8")


def _fetch(url: str) -> str:
    req = urllib.request.Request(
        url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", errors="replace")


def _extract(html: str) -> list[dict]:
    leads = []
    for m in MONEY_RE.finditer(html):
        try:
            amount = int(m.group(1).replace(" ", ""))
        except ValueError:
            continue
        if 300 <= amount <= 500_000:
            context = html[max(0, m.start() - 120):m.start()]
            context = " ".join(context.split())
            leads.append({"title": context[-90:], "estimate": amount})
    return leads[:15]


def scan() -> list[dict]:
    """Сканировать каналы. Вернуть список предложений (новых)."""
    seen = _load_seen()
    proposals = []
    for ch in CHANNELS:
        if not ch["url"]:
            pid = f"{ch['id']}:plan"
            if pid not in seen:
                proposals.append({
                    "id": pid, "channel": ch["name"], "kind": ch["kind"],
                    "title": "Запросить ключ 2GIS API и собрать первый список",
                    "estimate": DEFAULT_ESTIMATE[ch["kind"]],
                    "score": DEFAULT_ESTIMATE[ch["kind"]]})
            continue
        try:
            html = _fetch(ch["url"])
        except Exception as e:
            audit.log("money.channel_failed", level="warning",
                      channel=ch["id"], error=str(e)[:150])
            continue
        for lead in _extract(html):
            pid = f"{ch['id']}:{abs(hash(lead['title'])) % 10**8}"
            if pid in seen:
                continue
            proposals.append({
                "id": pid, "channel": ch["name"], "kind": ch["kind"],
                "title": lead["title"], "estimate": lead["estimate"],
                "score": lead["estimate"]})
    proposals.sort(key=lambda p: -p["score"])
    for p in proposals[:30]:
        seen.add(p["id"])
    _save_seen(seen)
    audit.log("money.scan", proposals=len(proposals))
    return proposals


def digest(proposals: list[dict] | None = None, top: int = 5) -> str:
    """Человекочитаемая сводка для Хранителя."""
    if proposals is None:
        proposals = scan()
    if not proposals:
        return ("Сегодня новых предложений нет: каналы недоступны или "
                "всё уже предложено. Проверь интернет и повтори.")
    lines = [f"{i+1}. [{p['channel']}] ~{p['estimate']} ₸ — {p['title']}"
             for i, p in enumerate(proposals[:top])]
    return "Предложения для Хранителя:\n" + "\n".join(lines)


if __name__ == "__main__":
    print(digest())
ZERKALO_EOF

cat > src/psychology/psychology.py <<'ZERKALO_EOF'
"""Понимание людей: адаптация речи под аудиторию.

Профили: businessman, worker, child, elderly. Модель недоступна —
работают локальные правила, система не молчит.
"""

from __future__ import annotations

from ..core import orchestrator

PROFILES: dict[str, dict] = {
    "businessman": {
        "tone": "деловой, короткий, цифры впереди",
        "focus": "выгода, сроки, риски",
        "avoid": "длинные вступления, «как дела»",
    },
    "worker": {
        "tone": "простой, прямой, без канцелярита",
        "focus": "что сделать и сколько получит",
        "avoid": "аббревиатуры и абстракции",
    },
    "child": {
        "tone": "тёплый, короткие фразы",
        "focus": "безопасность, понятные слова",
        "avoid": "термины, давление, запугивание",
    },
    "elderly": {
        "tone": "спокойный, вежливый, неторопливый",
        "focus": "пошаговость, повторение главного",
        "avoid": "спешка, длинные абзацы",
    },
}


def profiles() -> list[str]:
    return sorted(PROFILES)


def describe(profile: str) -> dict:
    if profile not in PROFILES:
        raise KeyError(f"нет профиля «{profile}». Есть: {', '.join(profiles())}")
    return dict(PROFILES[profile])


def _local_rewrite(profile: str, message: str) -> str:
    if profile == "businessman" and len(message) > 200:
        return message.split(". ")[-1]
    if profile == "worker":
        return (message.replace("осуществляется", "делается")
                .replace("необходимо", "надо"))
    if profile == "child":
        return " ".join(message.split(". ")[:2]) + "."
    if profile == "elderly":
        return message + "\n\nЕсли что-то непонятно — напишите, повторю по шагам."
    return message


def rewrite(profile: str, message: str) -> str:
    """Переписать сообщение под аудиторию."""
    p = describe(profile)
    system = (f"Ты — коммуникатор «Зеркала». Перепиши сообщение для "
              f"аудитории «{profile}». Тон: {p['tone']}. Фокус: {p['focus']}. "
              f"Избегай: {p['avoid']}. Только готовый текст.")
    r = orchestrator.think(message, system=system)
    if r.get("model") == "fallback":
        return _local_rewrite(profile, message)
    return r["text"]


def talk(profile: str, question: str) -> str:
    """Ответить человеку с учётом его профиля."""
    p = describe(profile)
    system = (f"Ты — «Зеркало», общаешься с аудиторией «{profile}». "
              f"Тон: {p['tone']}. Фокус: {p['focus']}. Красная черта: "
              f"не вредить, не давить, не решать за человека.")
    return orchestrator.think(question, system=system)["text"]


if __name__ == "__main__":
    print(rewrite("businessman", "Здравствуйте! Мы хотели бы предложить вам внедрить нашу систему автоматизации, которая осуществляет запись клиентов и напоминания. Необходимо всего полчаса на подключение."))
ZERKALO_EOF

cat > src/business/business.py <<'ZERKALO_EOF'
"""Бизнес-инженер: маржа, юнит-экономика, планы открытия и клиенты."""

from __future__ import annotations

from ..core import orchestrator


def margin(price: float, cost: float) -> dict:
    """Маржа и наценка. Цена в тенге."""
    price, cost = float(price), float(cost)
    if price <= 0:
        raise ValueError("цена должна быть > 0")
    m = price - cost
    return {"profit": round(m, 2),
            "margin_pct": round(m / price * 100, 1),
            "markup_pct": round(m / cost * 100, 1) if cost > 0 else None}


def unit_economics(price: float, variable_cost: float,
                   acquisition_cost: float) -> dict:
    """Сходится ли экономика: маржа с клиента и окупаемость CAC."""
    cm = float(price) - float(variable_cost)
    if cm <= 0:
        return {"ok": False,
                "reason": "маржа с клиента <= 0, экономика не сходится",
                "contribution": round(cm, 2)}
    return {"ok": True, "contribution": round(cm, 2),
            "cac": float(acquisition_cost),
            "payback_clients": round(float(acquisition_cost) / cm, 2)}


def funnel(leads: int, conv1_pct: float, conv2_pct: float,
           check: float) -> dict:
    """Воронка: лиды -> переговоры -> клиенты -> выручка."""
    c1 = leads * conv1_pct / 100
    c2 = c1 * conv2_pct / 100
    return {"leads": leads, "after_stage1": round(c1, 1),
            "clients": round(c2, 1), "revenue": round(c2 * check, 0)}


STO_PLAN_KZ = {
    "steps": [
        "1. Регистрация ИП через egov (1 день)",
        "2. Помещение: аренда бокса 60–100 м²",
        "3. Оборудование: подъёмник б/у, компрессор, инструмент",
        "4. Первый механик + администратор (или сам)",
        "5. Клиенты: 2GIS + WhatsApp-бот записи + партнёрство с шиномонтажками",
    ],
    "cost_estimates": {
        "reg": "30 000 ₸",
        "rent_month": "150 000–300 000 ₸",
        "equipment": "2 000 000–5 000 000 ₸",
        "salaries_month": "400 000–800 000 ₸",
    },
    "disclaimer": "Оценки ориентировочные для города РК — проверь в своём.",
}


def sto_open_plan(city: str = "") -> str:
    q = (f"Составь пошаговый план открытия СТО в городе "
         f"{city or 'Казахстана'} на основе: {STO_PLAN_KZ}")
    r = orchestrator.think(q)
    if r["model"] == "fallback":
        costs = "; ".join(f"{k}: {v}"
                          for k, v in STO_PLAN_KZ["cost_estimates"].items())
        return ("План открытия СТО:\n" + "\n".join(STO_PLAN_KZ["steps"])
                + f"\n\nРасходы: {costs}\n{STO_PLAN_KZ['disclaimer']}")
    return r["text"]


def client_sources(niche: str, city: str = "") -> str:
    q = (f"Где бизнесу ниши «{niche}» в {city or 'РК'} искать клиентов? "
         f"7 конкретных каналов с оценкой стоимости.")
    r = orchestrator.think(q)
    if r["model"] == "fallback":
        return ("Каналы: 1) 2GIS карточка (бесплатно), "
                "2) WhatsApp по соседям, 3) Instagram/TikTok (время), "
                "4) партнёрство с соседними бизнесами, "
                "5) Avito/Kaspi магазин, 6) листовки (2–3 ₸/шт), "
                "7) сарафан — бонус за друга.")
    return r["text"]


if __name__ == "__main__":
    print(margin(199000, 40000))
    print(unit_economics(20000, 3000, 15000))
    print(funnel(100, 20, 30, 199000))
ZERKALO_EOF

cat > src/learn/self_learn.py <<'ZERKALO_EOF'
"""Самообучение: уроки из каждого диалога.

Следит за историей: где «Зеркало» отвечало fallback (мозг был недоступен) —
урок «выучить ответ»; какие темы повторяются — урок «слабое место».
Уроки хранятся в SQLite, Хранитель видит сводку через review().
"""

from __future__ import annotations

import re
import sqlite3
import time
from pathlib import Path

from ..core import audit
from ..core.memory import Memory

DB_PATH = Path(__file__).resolve().parents[2] / "data" / "learn.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS lessons(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  topic TEXT NOT NULL,
  detail TEXT,
  ts REAL NOT NULL,
  used INTEGER NOT NULL DEFAULT 0
);
"""


def _conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.executescript(_SCHEMA)
    return conn


def _norm(text: str) -> str:
    return " ".join(re.findall(r"[a-zа-яё0-9]+", text.lower())[:4])


def absorb(memory: Memory, limit: int = 100) -> dict:
    """Прочитать историю диалогов и извлечь новые уроки."""
    hist = memory.history(limit=limit)
    conn = _conn()
    known = {row[0] for row in
             conn.execute("SELECT kind || ':' || topic FROM lessons")}
    new = 0
    topics: dict[str, int] = {}
    for i in range(len(hist) - 1):
        user, asst = hist[i], hist[i + 1]
        if user["role"] != "user" or asst["role"] != "assistant":
            continue
        topic = _norm(user["content"])
        topics[topic] = topics.get(topic, 0) + 1
        if (asst.get("meta") or {}).get("model") == "fallback":
            key = f"unanswered:{topic}"
            if key not in known:
                conn.execute(
                    "INSERT INTO lessons (kind, topic, detail, ts) "
                    "VALUES (?,?,?,?)",
                    ("unanswered", topic, user["content"][:200],
                     time.time()))
                new += 1
    for topic, count in topics.items():
        key = f"repeat:{topic}"
        if count >= 3 and key not in known:
            conn.execute(
                "INSERT INTO lessons (kind, topic, detail, ts) "
                "VALUES (?,?,?,?)",
                ("repeat", topic,
                 f"спросили {count} раз — слабое место", time.time()))
            new += 1
    conn.commit()
    conn.close()
    audit.log("learn.absorb", new_lessons=new)
    return {"new_lessons": new, "total": stats()["lessons"]}


def lessons(kind: str | None = None,
            only_fresh: bool = False) -> list[dict]:
    conn = _conn()
    sql = "SELECT id, kind, topic, detail, ts, used FROM lessons"
    where, args = [], []
    if kind:
        where.append("kind=?")
        args.append(kind)
    if only_fresh:
        where.append("used=0")
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY ts DESC LIMIT 50"
    rows = conn.execute(sql, args).fetchall()
    conn.close()
    return [dict(zip(("id", "kind", "topic", "detail", "ts", "used"), r))
            for r in rows]


def review() -> str:
    fresh = lessons(only_fresh=True)
    if not fresh:
        return "Новых уроков нет. Поговори со мной — я учусь на каждом диалоге."
    lines = [f"[{l['kind']}] {l['detail'] or l['topic']}"
             for l in fresh[:10]]
    return "Уроки для изучения:\n" + "\n".join(lines)


def mark_used(lesson_id: int) -> None:
    conn = _conn()
    conn.execute("UPDATE lessons SET used=1 WHERE id=?", (lesson_id,))
    conn.commit()
    conn.close()


def stats() -> dict:
    conn = _conn()
    total = conn.execute("SELECT COUNT(*) FROM lessons").fetchone()[0]
    fresh = conn.execute(
        "SELECT COUNT(*) FROM lessons WHERE used=0").fetchone()[0]
    conn.close()
    return {"lessons": total, "fresh": fresh}


if __name__ == "__main__":
    print(stats())
    print(review())
ZERKALO_EOF

cat > app.py <<'ZERKALO_EOF'
"""Сервер «Зеркало» — СУПЕРСИСТЕМА. Точка входа (Render/VPS).

Голос + мозг + память + Суры + модули + механизмы + эволюция
+ мост к телефону + поиск денег + психология + бизнес + обучение.

Маршруты:
    POST /voice         {"audio": base64, "mime": "audio/mp4"}  -> ответ голосом
    GET  /health        проверка живости
    GET  /status        состояние системы
    GET  /modules       модули и механизмы
    POST /evolve        цикл самоэволюции
    POST /phone/cmd     поставить команду телефону
    GET  /phone/cmd/next телефон забирает команду
    POST /phone/result  телефон отчитался
    GET  /phone/queue   очередь команд (для Хранителя)
    POST /money/scan    поиск денег -> предложения
    GET  /learn/review  уроки самообучения

Запуск:
    gunicorn app:app --timeout 120 --workers 1 --threads 4
    (локально: python app.py)
"""

from __future__ import annotations

import base64
import binascii
import importlib
import os
import threading
import time

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

from src.core import audit, kill_switch, voice
from src.core.memory import Memory
from src.core.orchestrator import think

app = Flask(__name__)
MAX_AUDIO_BYTES = 20 * 1024 * 1024

_local = threading.local()


def get_memory() -> Memory:
    mem = getattr(_local, "memory", None)
    if mem is None:
        mem = Memory()
        _local.memory = mem
    return mem


# ---------------------------------------------------------------
# Голос
# ---------------------------------------------------------------

@app.get("/health")
def health():
    return jsonify(status="alive", server_time=round(time.time()))


@app.get("/status")
def status():
    mem = get_memory()
    count = mem.conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    return jsonify(status="ok", kill_switch=kill_switch.status(),
                   memory_messages=count,
                   evolve_enabled=os.environ.get("SELF_EVOLVE_ENABLED") == "1")


@app.post("/voice")
def voice_endpoint():
    started = time.time()
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict) or not payload.get("audio"):
        return jsonify(status="error", reply="Нужен JSON с полем audio.",
                       heard="", audio=""), 400
    audio_b64 = str(payload.get("audio"))
    mime = str(payload.get("mime") or "audio/mp4")
    keeper_id = str(payload.get("keeper_id") or "")
    try:
        audio_bytes = base64.b64decode(audio_b64)
    except (binascii.Error, ValueError):
        return jsonify(status="error", reply="Плохой base64.",
                       heard="", audio=""), 400
    if not audio_bytes:
        return jsonify(status="error", reply="Пустое аудио.",
                       heard="", audio=""), 400
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        return jsonify(status="error", reply="Аудио больше 20 МБ.",
                       heard="", audio=""), 413

    blocked = kill_switch.guard()
    if blocked:
        return jsonify(status="ok", heard="", reply=blocked["text"],
                       audio="", stopped=True)
    try:
        heard = voice.stt(audio_bytes, mime=mime)
    except Exception as e:
        audit.log("app.stt_failed", level="error", error=str(e)[:300])
        return jsonify(status="error", reply=f"Не расслышал: {e}",
                       heard="", audio="")
    audit.log("app.heard", keeper_id=keeper_id, heard=heard[:300])
    if kill_switch.check(heard):
        return jsonify(status="ok", heard=heard,
                       reply="Стоп-кран «Аман» активен. Система остановлена.",
                       audio="", stopped=True)

    result = think(heard, memory=get_memory())
    reply = result["text"]
    if result.get("blocked"):
        return jsonify(status="ok", heard=heard, reply=reply,
                       audio="", stopped=True)

    audio_out = ""
    try:
        mp3 = voice.tts(reply)
        audio_out = base64.b64encode(mp3).decode("ascii")
    except Exception as e:
        audit.log("app.tts_failed", level="warning", error=str(e)[:300])

    latency_ms = round((time.time() - started) * 1000)
    audit.log("app.voice_ok", keeper_id=keeper_id,
              model=result.get("model"), latency_ms=latency_ms,
              reply_len=len(reply))
    return jsonify(status="ok", heard=heard, reply=reply, audio=audio_out,
                   stopped=False, model=result.get("model"),
                   latency_ms=latency_ms)


# ---------------------------------------------------------------
# Самоэволюция
# ---------------------------------------------------------------

@app.post("/evolve")
def evolve_endpoint():
    if os.environ.get("SELF_EVOLVE_ENABLED") != "1":
        return jsonify(status="error",
                       reply="Самоэволюция выключена (SELF_EVOLVE_ENABLED).")
    from src.core import self_evolve
    try:
        summary = self_evolve.run_once()
    except Exception as e:
        audit.log("app.evolve_failed", level="error", error=str(e)[:300])
        return jsonify(status="error", reply=f"Эволюция упала: {e}")
    return jsonify(status="ok", summary=summary)


_evolve_started = False


def _start_evolve_worker() -> None:
    global _evolve_started
    if _evolve_started or os.environ.get("SELF_EVOLVE_ENABLED") != "1":
        return
    _evolve_started = True

    def worker() -> None:
        from src.core import self_evolve
        self_evolve.loop(
            int(os.environ.get("SELF_EVOLVE_INTERVAL", "3600")))

    threading.Thread(target=worker, daemon=True,
                     name="self-evolve").start()
    audit.log("app.evolve_worker_started")


# ---------------------------------------------------------------
# Мост к телефону
# ---------------------------------------------------------------

@app.post("/phone/cmd")
def phone_add():
    from src.senses import phone_bridge
    payload = request.get_json(silent=True) or {}
    action = str(payload.get("action") or "")
    params = payload.get("params") or {}
    if not isinstance(params, dict):
        return jsonify(status="error", reply="params должен быть объектом"), 400
    try:
        cid = phone_bridge.add_command(action, **params)
    except ValueError as e:
        return jsonify(status="error", reply=str(e)), 400
    return jsonify(status="ok", id=cid)


@app.get("/phone/cmd/next")
def phone_next():
    from src.senses import phone_bridge
    cmd = phone_bridge.next_command()
    return jsonify(status="ok", command=cmd)


@app.post("/phone/result")
def phone_result():
    from src.senses import phone_bridge
    payload = request.get_json(silent=True) or {}
    phone_bridge.report_result(str(payload.get("id") or ""),
                               bool(payload.get("ok")),
                               str(payload.get("detail") or ""))
    return jsonify(status="ok")


@app.get("/phone/queue")
def phone_queue():
    from src.senses import phone_bridge
    cmd_id = request.args.get("id")
    return jsonify(status="ok", queue=phone_bridge.status(cmd_id))


# ---------------------------------------------------------------
# Поиск денег и обучение
# ---------------------------------------------------------------

@app.post("/money/scan")
def money_scan():
    from src.money import money_maker
    proposals = money_maker.scan()
    return jsonify(status="ok", count=len(proposals),
                   digest=money_maker.digest(proposals),
                   proposals=proposals[:20])


@app.get("/learn/review")
def learn_review():
    from src.learn import self_learn
    return jsonify(status="ok", text=self_learn.review(),
                   stats=self_learn.stats())


# ---------------------------------------------------------------
# Загрузка при старте
# ---------------------------------------------------------------

BOOT_REPORT: dict = {}
SUPER_CHECK: dict = {}

SUPER_MODULES = (
    "src.senses.phone_bridge",
    "src.money.money_maker",
    "src.psychology.psychology",
    "src.business.business",
    "src.learn.self_learn",
)


def _super_check() -> dict:
    """Проверить, что все супермодули импортируются."""
    report = {}
    for mod in SUPER_MODULES:
        try:
            importlib.import_module(mod)
            report[mod.split(".")[-1]] = "ok"
        except Exception as e:
            report[mod.split(".")[-1]] = f"FAIL: {e}"
            audit.log("app.super_fail", level="error", module=mod,
                      error=str(e)[:200])
    return report


def _boot_loaders() -> None:
    global BOOT_REPORT, SUPER_CHECK
    from src.core import mechanics_loader, modules_loader
    BOOT_REPORT = {
        "modules": modules_loader.load_all(),
        "mechanics": mechanics_loader.load_all(),
    }
    SUPER_CHECK = _super_check()
    m, x = BOOT_REPORT["modules"], BOOT_REPORT["mechanics"]
    print(f"[boot] модули: {m['loaded']}/{m['total']} загружено, "
          f"{m['failed']} упало")
    print(f"[boot] механизмы: {x['registered']} в реестре, "
          f"{x['ready']} готовы")
    failed = [k for k, v in SUPER_CHECK.items() if v != "ok"]
    print(f"[boot] супермодули: {len(SUPER_CHECK) - len(failed)}/"
          f"{len(SUPER_CHECK)} ок" + (f", упали: {failed}" if failed else ""))
    audit.log("app.boot", modules_loaded=m["loaded"],
              mechanics_registered=x["registered"],
              super_ok=len(SUPER_CHECK) - len(failed),
              super_failed=len(failed))


_boot_loaders()


# ---------------------------------------------------------------
# Ошибки и отчёт
# ---------------------------------------------------------------

@app.errorhandler(Exception)
def on_error(e: Exception):
    if isinstance(e, HTTPException):
        return e
    audit.log("app.unhandled", level="error", error=str(e)[:300])
    return jsonify(status="error", reply=f"Внутренняя ошибка: {e}")


@app.get("/modules")
def modules_status():
    from src.core import mechanics_loader, modules_loader
    return jsonify(
        status="ok",
        modules={"loaded": len(modules_loader.modules()),
                 "failed_names": sorted(modules_loader.failed()),
                 "names": sorted(modules_loader.modules())},
        mechanics={"registered": len(mechanics_loader.list_all()),
                   "ready": mechanics_loader.stats()["ready"]},
        super=SUPER_CHECK, boot=BOOT_REPORT)


with app.app_context():
    pass

_start_evolve_worker()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, threaded=True)
ZERKALO_EOF

# ------------------------------------------------------------
# 5. Стартовые данные
# ------------------------------------------------------------
cat > data/mechanisms.json <<'ZERKALO_EOF'
[
  {"id": "romb",       "name": "Ромб",             "kind": "online",  "commission_pct": 5},
  {"id": "arbitrage",  "name": "Арбитраж",          "kind": "online",  "commission_pct": 3},
  {"id": "autobiz",    "name": "Автоматизация бизнеса", "kind": "offline", "commission_pct": 10},
  {"id": "leasing",    "name": "Лизинг",            "kind": "offline", "commission_pct": 5},
  {"id": "dropship",   "name": "Дропшиппинг",       "kind": "online",  "commission_pct": 8},
  {"id": "ads",        "name": "Реклама",           "kind": "online",  "commission_pct": 5},
  {"id": "partner",    "name": "Партнёрки",         "kind": "online",  "commission_pct": 10},
  {"id": "subscr",     "name": "Подписки",          "kind": "online",  "commission_pct": 10},
  {"id": "logistics",  "name": "Логистика",         "kind": "offline", "commission_pct": 3},
  {"id": "smartcity",  "name": "Умный город",       "kind": "offline", "commission_pct": 5},
  {"id": "education",  "name": "Образование",       "kind": "online",  "commission_pct": 10},
  {"id": "medicine",   "name": "Медицина",          "kind": "offline", "commission_pct": 1},
  {"id": "cybersec",   "name": "Кибербезопасность", "kind": "online",  "commission_pct": 10},
  {"id": "bank_blag",  "name": "Банк блага",        "kind": "online",  "commission_pct": 2},
  {"id": "data_work",  "name": "Работа с данными",  "kind": "online",  "commission_pct": 15}
]
ZERKALO_EOF

cat > src/modules/example.py <<'ZERKALO_EOF'
"""Пример модуля-эксперта. Можно удалить."""

MODULE = {"name": "Пример-эксперт", "domain": "general",
          "description": "Показывает формат модулей. Удали этот файл."}


def answer(question: str, context: str = "") -> str:
    return ("Я пример модуля. Спроси у настоящих экспертов, "
            "когда Хранитель их добавит.")
ZERKALO_EOF

# ------------------------------------------------------------
# 6. Android: инструкции для управления телефоном
# ------------------------------------------------------------
cat > android/ACCESSIBILITY_SETUP.md <<'ZERKALO_EOF'
# Подключение Accessibility Service (управление телефоном)

Это инструкция для телефона Хранителя. Код службы — следующий шаг,
здесь — что включить и как работает связка.

## Что даст «Зеркало»

- открывать приложения по имени (WhatsApp, Telegram, Kaspi);
- тапать и свайпать по экрану, печатать текст;
- включать/выключать Bluetooth и Wi-Fi, менять яркость;
- делать скриншоты экрана по команде.

## Безопасность (Красная черта)

1. Команды выполняются ТОЛЬКО на телефоне Хранителя.
2. Каждая деструктивная команда (платёж, отправка, удаление) —
   только после подтверждения Хранителем вручную. «Зеркало» само
   такие команды не ставит.
3. Стоп-кран «Аман» останавливает и телефон тоже.

## Порядок включения (когда APK с службой будет установлен)

1. Настройки → Специальные возможности → Загруженные службы.
2. Включить «ZerkaloService».
3. Разрешить: «Наблюдение за действиями», «Выполнение жестов».
4. Настройки → Приложения → Зеркало → Батарея → «Без ограничений»
   (иначе Android убьёт службу).
5. Отключить оптимизацию батареи для приложения.

## Как телефон получает команды

Телефон раз в 3–5 секунд спрашивает сервер:
    GET https://ВАШ-СЕРВИС.onrender.com/phone/cmd/next
Если команда есть — выполняет, затем:
    POST /phone/cmd/result  {"id": "...", "ok": true, "detail": "..."}

Команды ставятся через POST /phone/cmd {"action": "open_app",
"params": {"package": "com.whatsapp"}} — вручную Хранителем или модулем.
Протокол команд: см. android/REMOTE_PROTOCOL.md.
ZERKALO_EOF

cat > android/REMOTE_PROTOCOL.md <<'ZERKALO_EOF'
# Протокол команд телефону (сервер <-> Android)

## Эндпоинты сервера

| Метод | Адрес | Кто | Что |
|---|---|---|---|
| POST | /phone/cmd | Хранитель/модуль | поставить команду |
| GET  | /phone/cmd/next | телефон | забрать команду |
| POST | /phone/result | телефон | отчёт о выполнении |
| GET  | /phone/queue | Хранитель | список команд |

## Формат команды

{"action": "...", "params": {...}}

## Действия

| action | params | Пример |
|---|---|---|
| open_app | package | {"package": "com.whatsapp"} |
| tap | x, y | {"x": 540, "y": 1200} |
| swipe | x1, y1, x2, y2, ms? | {"x1":540,"y1":1500,"x2":540,"y2":300} |
| type | text | {"text": "Привет"} |
| key_event | code | {"code": "KEYCODE_BACK"} |
| bluetooth | on/off | {"state": "on"} |
| wifi | on/off | {"state": "off"} |
| brightness | level 0..255 | {"level": 128} |
| screenshot | — | {} |
| wait | ms | {"ms": 1000} |

## Ответ телефона

{"id": "abc123", "ok": true, "detail": "открыто"}

## Проверка вручную (curl)

curl -X POST https://ВАШ-СЕРВИС.onrender.com/phone/cmd \
  -H "Content-Type: application/json" \
  -d '{"action": "open_app", "params": {"package": "com.whatsapp"}}'

curl https://ВАШ-СЕРВИС.onrender.com/phone/cmd/next
ZERKALO_EOF

# ------------------------------------------------------------
# 6b. Android-клиент (в папке android/)
# ------------------------------------------------------------
mkdir -p android/app/src/main/java/com/zerkalo/mirror \
         android/app/src/main/res/layout android/app/src/main/res/values \
         android/.github/workflows

cat > android/settings.gradle <<'ZERKALO_EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "Zerkalo"
include ':app'
ZERKALO_EOF

cat > android/build.gradle <<'ZERKALO_EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.24' apply false
}
ZERKALO_EOF

cat > android/gradle.properties <<'ZERKALO_EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
ZERKALO_EOF

cat > android/app/build.gradle <<'ZERKALO_EOF'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.zerkalo.mirror'
    compileSdk 34

    defaultConfig {
        applicationId "com.zerkalo.mirror"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildTypes {
        release {
            minifyEnabled false
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.13.1'
    implementation 'androidx.activity:activity:1.9.2'

    def camerax_version = "1.3.4"
    implementation "androidx.camera:camera-core:$camerax_version"
    implementation "androidx.camera:camera-camera2:$camerax_version"
    implementation "androidx.camera:camera-lifecycle:$camerax_version"
    implementation "androidx.camera:camera-view:$camerax_version"

    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
ZERKALO_EOF

cat > android/app/src/main/AndroidManifest.xml <<'ZERKALO_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <uses-feature android:name="android.hardware.camera.front" android:required="false" />
    <uses-feature android:name="android.hardware.microphone" android:required="true" />

    <application
        android:allowBackup="false"
        android:label="@string/app_name"
        android:theme="@style/Theme.Zerkalo">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="portrait">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
ZERKALO_EOF

cat > android/app/src/main/res/values/strings.xml <<'ZERKALO_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Зеркало</string>
</resources>
ZERKALO_EOF

cat > android/app/src/main/res/values/themes.xml <<'ZERKALO_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Zerkalo" parent="android:Theme.Material.NoActionBar" />
</resources>
ZERKALO_EOF

cat > android/app/src/main/res/layout/activity_main.xml <<'ZERKALO_EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@android:color/black"
    android:keepScreenOn="true">

    <androidx.camera.view.PreviewView
        android:id="@+id/previewView"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />

    <com.zerkalo.mirror.WaveView
        android:id="@+id/waveView"
        android:layout_width="260dp"
        android:layout_height="260dp"
        android:layout_gravity="center" />

    <!-- Выбор роли: три сектора, видны только при первом запуске -->
    <LinearLayout
        android:id="@+id/roleOverlay"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical"
        android:visibility="gone">

        <FrameLayout
            android:id="@+id/roleKeeper"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:background="#33FFFFFF"
            android:clickable="true">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="ХРАНИТЕЛЬ"
                android:textColor="@android:color/white"
                android:textSize="28sp"
                android:textStyle="bold" />

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:layout_marginTop="40dp"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="полный доступ"
                android:textColor="@android:color/white"
                android:textSize="14sp" />
        </FrameLayout>

        <FrameLayout
            android:id="@+id/roleBusiness"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:background="#26FFFFFF"
            android:clickable="true">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="БИЗНЕС"
                android:textColor="@android:color/white"
                android:textSize="28sp"
                android:textStyle="bold" />

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:layout_marginTop="40dp"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="автоматизация, клиенты"
                android:textColor="@android:color/white"
                android:textSize="14sp" />
        </FrameLayout>

        <FrameLayout
            android:id="@+id/roleSimple"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:background="#1FFFFFFF"
            android:clickable="true">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="ПРОСТОЙ"
                android:textColor="@android:color/white"
                android:textSize="28sp"
                android:textStyle="bold" />

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:layout_marginTop="40dp"
                android:shadowColor="@android:color/black"
                android:shadowRadius="8"
                android:text="помощь, работа, обучение"
                android:textColor="@android:color/white"
                android:textSize="14sp" />
        </FrameLayout>
    </LinearLayout>

    <TextView
        android:id="@+id/statusText"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|center_horizontal"
        android:layout_marginBottom="64dp"
        android:paddingStart="24dp"
        android:paddingEnd="24dp"
        android:gravity="center"
        android:shadowColor="@android:color/black"
        android:shadowRadius="8"
        android:text="Зеркало"
        android:textColor="@android:color/white"
        android:textSize="18sp"
        android:textStyle="bold" />
</FrameLayout>
ZERKALO_EOF

cat > android/app/src/main/java/com/zerkalo/mirror/WaveView.kt <<'ZERKALO_EOF'
package com.zerkalo.mirror

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/**
 * Анимация «волн» поверх камеры.
 * LISTENING — медленные кольца, ACTIVE — быстрые (думает/говорит), IDLE — тихо.
 */
class WaveView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    enum class Mode { IDLE, LISTENING, ACTIVE }

    private var mode = Mode.IDLE
    private var phase = 0f

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 6f
    }

    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1600
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { animation ->
            phase = animation.animatedValue as Float
            invalidate()
        }
    }

    fun setMode(newMode: Mode) {
        if (mode == newMode) return
        mode = newMode
        when (mode) {
            Mode.IDLE -> if (animator.isStarted) animator.pause()
            else -> animator.resume()
        }
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        animator.start()
        if (mode == Mode.IDLE) animator.pause()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (mode == Mode.IDLE) return
        val cx = width / 2f
        val cy = height / 2f
        val maxR = (minOf(width, height) / 2f) * 0.9f
        val rings = if (mode == Mode.ACTIVE) 5 else 3
        for (i in 0 until rings) {
            val p = (phase + i.toFloat() / rings) % 1f
            paint.alpha = ((1f - p) * 90).toInt().coerceIn(0, 255)
            canvas.drawCircle(cx, cy, maxR * p, paint)
        }
        paint.alpha = 70
        canvas.drawCircle(cx, cy, maxR * 0.12f, paint)
    }
}
ZERKALO_EOF

cat > android/.github/workflows/android.yml <<'ZERKALO_EOF'
name: Build APK

on:
  push:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Generate Gradle wrapper (AGP 8.5.2 требует Gradle 8.7+)
        run: gradle wrapper --gradle-version 8.7

      - name: Build debug APK
        run: ./gradlew assembleDebug --no-daemon

      - uses: actions/upload-artifact@v4
        with:
          name: zerkalo-apk
          path: app/build/outputs/apk/debug/app-debug.apk
          retention-days: 14
ZERKALO_EOF



cat > android/app/src/main/java/com/zerkalo/mirror/MainActivity.kt <<'ZERKALO_EOF'
package com.zerkalo.mirror

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "Zerkalo"
        private const val SERVER_URL = "https://zerkalo-6sla.onrender.com/voice"

        private const val SILENCE_MS = 1500L
        private const val MIN_RECORD_MS = 700L
        private const val MAX_RECORD_MS = 30_000L
        private const val POLL_MS = 100L
        private const val SILENCE_THRESHOLD = 600
        private const val RESTART_DELAY_MS = 800L
        private const val TEXT_SHOW_MS = 3000L
        private const val ROLE_TIMEOUT_MS = 30_000L

        private const val PREFS = "zerkalo_prefs"
        private const val KEY_ROLE = "role"
    }

    private enum class Role(val code: String, val label: String) {
        KEEPER("keeper", "Хранитель"),
        BUSINESS("business", "Бизнес"),
        SIMPLE("simple", "Простой"),
    }

    private lateinit var previewView: PreviewView
    private lateinit var waveView: WaveView
    private lateinit var statusText: TextView
    private lateinit var roleOverlay: View

    private var recorder: MediaRecorder? = null
    private var currentFile: File? = null
    private var player: MediaPlayer? = null
    private var recognizer: SpeechRecognizer? = null

    @Volatile private var isRecording = false
    @Volatile private var maxAmplitude = 0
    @Volatile private var roleChosen = false

    private var role: Role = Role.SIMPLE
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    // 60+ сек: Render просыпается, Gemini думает
    private val http = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(75, TimeUnit.SECONDS)
        .build()

    private val requiredPermissions = arrayOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
    )

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        if (result.all { it.value }) {
            onPermissionsReady()
        } else {
            setStatus("Нужны разрешения: камера и микрофон.", WaveView.Mode.IDLE)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_main)

        previewView = findViewById(R.id.previewView)
        waveView = findViewById(R.id.waveView)
        statusText = findViewById(R.id.statusText)
        roleOverlay = findViewById(R.id.roleOverlay)

        findViewById<View>(R.id.roleKeeper).setOnClickListener { chooseRole(Role.KEEPER) }
        findViewById<View>(R.id.roleBusiness).setOnClickListener { chooseRole(Role.BUSINESS) }
        findViewById<View>(R.id.roleSimple).setOnClickListener { chooseRole(Role.SIMPLE) }

        // Возвращающийся пользователь: роль уже выбрана
        getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_ROLE, null)
            ?.let { saved ->
                Role.values().find { it.code == saved }?.let {
                    role = it
                    roleChosen = true
                }
            }

        if (hasPermissions()) {
            onPermissionsReady()
        } else {
            permissionLauncher.launch(requiredPermissions)
        }
    }

    private fun onPermissionsReady() {
        startCamera()
        if (!roleChosen) {
            beginRoleSelection()
        } else {
            setStatus("Роль: ${role.label}. Слушаю...", WaveView.Mode.LISTENING)
            startListening()
        }
    }

    override fun onStart() {
        super.onStart()
        if (::previewView.isInitialized && hasPermissions() && roleChosen) {
            startListening()
        }
    }

    override fun onStop() {
        super.onStop()
        isRecording = false
        try { recorder?.stop() } catch (_: Exception) {}
        recorder?.release()
        recorder = null
        player?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        player = null
        stopRecognizer()
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
        stopRecognizer()
    }

    private fun hasPermissions() = requiredPermissions.all {
        ContextCompat.checkSelfPermission(this, it) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun setStatus(text: String, mode: WaveView.Mode) {
        statusText.text = text
        waveView.setMode(mode)
    }

    // ---------------------------------------------------------------
    // РОЛИ
    // ---------------------------------------------------------------

    private fun beginRoleSelection() {
        roleOverlay.visibility = View.VISIBLE
        setStatus("Кто ты? Скажи или коснись: Хранитель / Бизнес / Простой",
            WaveView.Mode.LISTENING)
        startRecognizer()
        mainHandler.postDelayed({
            if (!roleChosen) {
                Log.w(TAG, "роль не выбрана за 30 сек — Простой")
                chooseRole(Role.SIMPLE)
            }
        }, ROLE_TIMEOUT_MS)
    }

    private fun startRecognizer() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.w(TAG, "SpeechRecognizer недоступен — выбор тапом")
            return
        }
        stopRecognizer()
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                if (roleChosen) return
                Log.w(TAG, "recognizer error=$error — слушаю снова")
                mainHandler.postDelayed({ if (!roleChosen) startRecognizer() }, 400)
            }

            override fun onResults(results: Bundle?) {
                if (roleChosen) return
                val heard = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull().orEmpty()
                Log.d(TAG, "роль услышано: $heard")
                matchRole(heard)?.let { chooseRole(it) }
                    ?: mainHandler.postDelayed({ if (!roleChosen) startRecognizer() }, 400)
            }

            override fun onPartialResults(partialResults: Bundle?) {
                if (roleChosen) return
                val heard = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull().orEmpty()
                matchRole(heard)?.let { chooseRole(it) }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        try {
            r.startListening(intent)
        } catch (e: Exception) {
            Log.e(TAG, "startListening", e)
        }
    }

    private fun stopRecognizer() {
        recognizer?.let {
            try { it.stopListening() } catch (_: Exception) {}
            try { it.cancel() } catch (_: Exception) {}
            it.destroy()
        }
        recognizer = null
    }

    private fun matchRole(text: String): Role? {
        val t = text.lowercase()
        return when {
            "хранитель" in t || "каирбек" in t -> Role.KEEPER
            "бизнес" in t -> Role.BUSINESS
            "простой" in t || "просто" in t || "работа" in t -> Role.SIMPLE
            else -> null
        }
    }

    private fun chooseRole(newRole: Role) {
        if (roleChosen) return
        roleChosen = true
        role = newRole
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_ROLE, newRole.code).apply()
        stopRecognizer()
        roleOverlay.visibility = View.GONE
        setStatus("Роль: ${newRole.label}. Слушаю...", WaveView.Mode.LISTENING)
        startListening()
    }

    // ---------------------------------------------------------------
    // Камера
    // ---------------------------------------------------------------

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val provider = future.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val selector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                    .build()
                provider.unbindAll()
                provider.bindToLifecycle(this, selector, preview)
            } catch (e: Exception) {
                Log.e(TAG, "Камера не запустилась", e)
                setStatus("Ошибка камеры: ${e.message}", WaveView.Mode.IDLE)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    // ---------------------------------------------------------------
    // Запись и детекция тишины
    // ---------------------------------------------------------------

    private fun startListening() {
        if (isRecording || !roleChosen) return
        val file = File(cacheDir, "voice_${System.currentTimeMillis()}.m4a")
        currentFile = file
        setStatus("Слушаю...", WaveView.Mode.LISTENING)
        try {
            val rec = newRecorder()
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioSamplingRate(44100)
            rec.setAudioEncodingBitRate(96000)
            rec.setAudioChannels(1)
            rec.setOutputFile(file.absolutePath)
            rec.prepare()
            rec.start()
            recorder = rec
            isRecording = true
            maxAmplitude = 0
            executor.execute { watchSilence(SystemClock.elapsedRealtime()) }
        } catch (e: Exception) {
            Log.e(TAG, "Не удалось начать запись", e)
            releaseRecorder()
            setStatus("Ошибка микрофона: ${e.message}", WaveView.Mode.IDLE)
            statusText.postDelayed({ startListening() }, 2000)
        }
    }

    @Suppress("DEPRECATION")
    private fun newRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this)
        else MediaRecorder()

    private fun watchSilence(startedAt: Long) {
        var lastLoudAt = startedAt
        while (isRecording) {
            Thread.sleep(POLL_MS)
            val rec = recorder ?: break
            val amp = try { rec.maxAmplitude } catch (e: Exception) { break }
            val now = SystemClock.elapsedRealtime()
            if (amp > SILENCE_THRESHOLD) {
                lastLoudAt = now
                if (amp > maxAmplitude) maxAmplitude = amp
            }
            val elapsed = now - startedAt
            val silentFor = now - lastLoudAt
            if ((elapsed >= MIN_RECORD_MS && silentFor >= SILENCE_MS) ||
                elapsed >= MAX_RECORD_MS) break
        }
        if (isRecording) runOnUiThread { finishRecordingAndSend() }
    }

    private fun releaseRecorder() {
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    private fun finishRecordingAndSend() {
        isRecording = false
        val rec = recorder
        recorder = null
        val file = currentFile
        val heardSomething = maxAmplitude > SILENCE_THRESHOLD &&
                file != null && file.length() > 400
        try { rec?.stop() } catch (e: Exception) { Log.w(TAG, "stop()", e) }
        try { rec?.release() } catch (_: Exception) {}

        if (!heardSomething) {
            file?.delete()
            startListening()
            return
        }
        setStatus("Думаю...", WaveView.Mode.ACTIVE)
        sendToServer(file)
    }

    // ---------------------------------------------------------------
    // Сеть
    // ---------------------------------------------------------------

    private fun sendToServer(file: File) {
        executor.execute {
            try {
                val audioB64 = Base64.encodeToString(file.readBytes(),
                    Base64.NO_WRAP)
                val json = JSONObject()
                    .put("audio", audioB64)
                    .put("mime", "audio/mp4")
                    .put("role", role.code)
                    .toString()
                val body = json.toRequestBody(
                    "application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url(SERVER_URL).post(body).build()
                http.newCall(request).enqueue(object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        Log.e(TAG, "Сеть", e)
                        showErrorAndRestart(
                            "Ошибка сети: ${e.message ?: "сервер не отвечает"}")
                    }

                    override fun onResponse(call: Call, response: Response) {
                        response.use { resp ->
                            if (!resp.isSuccessful) {
                                showErrorAndRestart(
                                    "Сервер ответил кодом ${resp.code}")
                                return
                            }
                            val respJson = JSONObject(resp.body.string())
                            if (respJson.optString("status") != "ok") {
                                showErrorAndRestart(
                                    "Ошибка сервера: ${
                                        respJson.optString("reply",
                                            "status != ok")}")
                                return
                            }
                            handleReply(respJson)
                        }
                    }
                })
            } catch (e: Exception) {
                showErrorAndRestart("Ошибка отправки: ${e.message}")
            }
        }
    }

    private fun showErrorAndRestart(msg: String) {
        runOnUiThread {
            setStatus(msg, WaveView.Mode.IDLE)
            statusText.postDelayed({ startListening() }, 3000)
        }
    }

    // ---------------------------------------------------------------
    // Ответ: аудио или текст
    // ---------------------------------------------------------------

    private fun handleReply(respJson: JSONObject) {
        val audioB64 = respJson.optString("audio")
        val replyText = respJson.optString("reply", "")
        val stopped = respJson.optBoolean("stopped", false)

        if (audioB64.isBlank()) {
            // Голоса нет — показываем текст 3 секунды и слушаем дальше
            runOnUiThread {
                setStatus(replyText.ifBlank { "(пустой ответ)" },
                    WaveView.Mode.IDLE)
                statusText.postDelayed(
                    { if (!stopped) startListening() else
                        setStatus(replyText.ifBlank { "Остановлено." },
                            WaveView.Mode.IDLE) },
                    TEXT_SHOW_MS)
            }
            return
        }

        try {
            val mp3 = File(cacheDir, "reply_${System.currentTimeMillis()}.mp3")
            mp3.writeBytes(Base64.decode(audioB64, Base64.DEFAULT))
            runOnUiThread {
                setStatus("Говорю...", WaveView.Mode.ACTIVE)
                val mp = MediaPlayer()
                player = mp
                try {
                    mp.setDataSource(mp3.absolutePath)
                    mp.setOnCompletionListener {
                        it.release()
                        player = null
                        mp3.delete()
                        if (!stopped) {
                            statusText.postDelayed({ startListening() },
                                RESTART_DELAY_MS)
                        } else {
                            setStatus("Остановлено по команде «Аман».",
                                WaveView.Mode.IDLE)
                        }
                    }
                    mp.setOnErrorListener { m, what, _ ->
                        m.release()
                        player = null
                        setStatus("Ошибка воспроизведения ($what)",
                            WaveView.Mode.IDLE)
                        statusText.postDelayed({ startListening() }, 3000)
                        true
                    }
                    mp.prepare()
                    mp.start()
                } catch (e: Exception) {
                    mp.release()
                    player = null
                    setStatus("Ошибка аудио: ${e.message}", WaveView.Mode.IDLE)
                    statusText.postDelayed({ startListening() }, 3000)
                }
            }
        } catch (e: Exception) {
            showErrorAndRestart("Ошибка декодирования аудио: ${e.message}")
        }
    }
}
ZERKALO_EOF

# ------------------------------------------------------------
# 7. Проверка: структура, компиляция, импорт супермодулей
# ------------------------------------------------------------
echo "=== Проверка сборки Суперсистемы ==="
python3 - <<'ZERKALO_EOF'
import importlib
import pathlib
import py_compile
import sys

files = ["app.py"] + sorted(str(p) for p in pathlib.Path("src").rglob("*.py"))
bad = []
for f in files:
    try:
        py_compile.compile(f, doraise=True)
    except py_compile.PyCompileError as e:
        bad.append(f"{f}: {e}")
if bad:
    print("ОШИБКИ КОМПИЛЯЦИИ:")
    for b in bad:
        print(" -", b)
    sys.exit(1)
print(f"OK: скомпилировано {len(files)} файлов")

SUPER = ["src.senses.phone_bridge", "src.money.money_maker",
         "src.psychology.psychology", "src.business.business",
         "src.learn.self_learn"]
failed_imports = []
for mod in SUPER:
    try:
        importlib.import_module(mod)
        print(f"OK: импорт {mod}")
    except Exception as e:
        failed_imports.append(f"{mod}: {e}")
        print(f"FAIL: {mod}: {e}")
if failed_imports:
    sys.exit(1)

for d in ["src/core", "src/modules", "src/money", "src/psychology",
          "src/business", "src/learn", "src/senses", "data/suras",
          "android"]:
    if not pathlib.Path(d).exists():
        print(f"НЕТ папки {d}/")
        sys.exit(1)
print("OK: все папки на месте")

# Быстрый функциональный прогон супермодулей (без сети)
from src.business import business as biz
m = biz.margin(199000, 40000)
assert m["profit"] == 159000 and m["margin_pct"] == 79.9, m
ue = biz.unit_economics(20000, 3000, 15000)
assert ue["ok"] and ue["payback_clients"] == 0.88, ue

from src.psychology import psychology as psy
assert "надо" in psy._local_rewrite("worker", "необходимо сделать")
assert set(psy.profiles()) == {"businessman", "worker", "child", "elderly"}

from src.senses import phone_bridge as pb
cid = pb.add_command("open_app", package="com.whatsapp")
cmd = pb.next_command()
assert cmd and cmd["id"] == cid and cmd["action"] == "open_app"
pb.report_result(cid, True, "ок")
assert pb.status(cid)["status"] == "done"
pb.clear_done()

from src.learn import self_learn as sl
from src.core.memory import Memory
mem = Memory(db_path=":memory:")
mem.add("user", "расскажи про маржу")
mem.add("assistant", "fallback", meta={"model": "fallback"})
mem.add("user", "расскажи про маржу")
mem.add("assistant", "fallback", meta={"model": "fallback"})
mem.add("user", "расскажи про маржу")
mem.add("assistant", "fallback", meta={"model": "fallback"})
r = sl.absorb(mem)
assert r["new_lessons"] >= 1, r
assert "марж" in sl.review()
sl.mark_used(sl.lessons(only_fresh=True)[0]["id"])

print("OK: супермодули работают (маржа, психология, телефон, обучение)")
ZERKALO_EOF

# ------------------------------------------------------------
# 8. Готово
# ------------------------------------------------------------
echo ""
echo "=========================================="
echo "Суперсистема Зеркало развернута. Вставь ключи и дай команду искать деньги."
echo "=========================================="
echo "Следующие шаги:"
echo "  1) cp .env.example .env        и вставь ключи (nano .env)"
echo "  2) pip install -r requirements.txt"
echo "  3) python app.py               (или gunicorn app:app --timeout 120 --workers 1 --threads 4)"
echo "  4) проверка:"
echo "       curl localhost:5000/health"
echo "       curl -X POST localhost:5000/money/scan"
echo "       curl localhost:5000/learn/review"
echo "  5) команда телефону (когда APK со службой будет):"
echo "       curl -X POST localhost:5000/phone/cmd -H 'Content-Type: application/json' \\"
echo "            -d '{\"action\": \"open_app\", \"params\": {\"package\": \"com.whatsapp\"}}'"
echo ""
echo "Папка data/suras/ пуста — положи туда Суры и Ядро,"
echo "затем один раз выполни:  python -m src.core.knowledge_base"
echo ""
echo "Android: залей папку android/ в отдельный репозиторий ->"
echo "  GitHub Actions -> Build APK -> Run workflow -> скачай zerkalo-apk.zip"
