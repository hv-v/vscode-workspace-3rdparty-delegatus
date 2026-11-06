#!/usr/bin/env python3
"""kb.py — the MediaWiki mirror as one SQLite file, with keyword and vector search.

One file, two halves:

  host, standard library only
      sync.sh stores what it downloads here: init, put-pages, plan, prune,
      nav-map. Readers: page, status, search --keyword.
  container (the ipp-wiki-kb image, docker/wiki/: model +
  onnxruntime + sqlite-vec, no network; this file is mounted over /app/kb.py)
      index    pages whose `indexed` flag is 0 → sections → chunks, FTS5 rows
               and embeddings; then the flag goes to 1
      search   keyword and vector hits fused into one ranking
      serve    keep the model loaded and answer search / index over a Unix
               socket; exits after --idle seconds without a request. The host
               side reaches it when $KB_SOCKET is set (kb.sh sets it).

The database: $KB_DB (sync.sh and kb.sh set it to .wiki/.db/wiki.db).

  pages          one row per page: revid, updated_at (UTC timestamp), the
                 wikitext source, and `indexed` (0/1): 0 whenever the page
                 changed, 1 once chunks and vectors match
  chunks         FTS5: one row per section window
  chunks_vec     sqlite-vec, same rowids as chunks — created by the container
                 only; the host never touches it
"""

import argparse
import contextlib
import datetime as dt
import html
import io
import json
import os
import re
import signal
import socket
import sqlite3
import sys
import traceback

SCHEMA_VERSION = 1
EMBED_DIM = 384           # multilingual-e5-small
CHUNK_CHARS = 1200        # well inside the model's 512 tokens
CHUNK_OVERLAP = 200
RRF_K = 60                # reciprocal-rank fusion constant
CANDIDATES = 50           # hits taken from each side before fusing
SERVED = {"search", "index", "ping"}   # what `serve` answers; the rest is host-only
EX_NO_SERVER = 75         # EX_TEMPFAIL: $KB_SOCKET set but nothing answers there

SCHEMA = """
CREATE TABLE IF NOT EXISTS pages (
    id            TEXT PRIMARY KEY,           -- MediaWiki pageid
    ns            INTEGER NOT NULL,
    ns_name       TEXT,
    title         TEXT NOT NULL,              -- full title, namespace prefix included
    revid         INTEGER NOT NULL,
    updated_at    TEXT NOT NULL,              -- the revision's timestamp, UTC, ISO 8601
    updated_by    TEXT,
    url           TEXT,
    categories    TEXT NOT NULL DEFAULT '[]', -- JSON ["Category name", …], prefix stripped
    body          TEXT NOT NULL,              -- wikitext, as served
    indexed       INTEGER NOT NULL DEFAULT 0 CHECK (indexed IN (0, 1)),
    indexed_at    TEXT,
    fetched_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS pages_ns ON pages (ns);
CREATE INDEX IF NOT EXISTS pages_title ON pages (title);
CREATE INDEX IF NOT EXISTS pages_pending ON pages (indexed);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5 (
    heading, text,
    page_id UNINDEXED, ord UNINDEXED, kind UNINDEXED,
    tokenize = 'unicode61 remove_diacritics 2'
);
"""


def die(message, code=1):
    print(f"kb: {message}", file=sys.stderr)
    sys.exit(code)


def now_utc():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def to_utc(stamp):
    """MediaWiki's '2026-10-27T15:54:40Z' → the same, normalised; '' stays ''."""
    if not stamp:
        return ""
    try:
        parsed = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return stamp
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(vec=False):
    path = os.environ.get("KB_DB")
    if not path:
        die("KB_DB is not set")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    if vec:
        import sqlite_vec  # container only
        db.enable_load_extension(True)
        sqlite_vec.load(db)
        db.enable_load_extension(False)
    return db


def init_schema(db):
    db.executescript(SCHEMA)
    db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    db.commit()


def open_db(vec=False):
    db = connect(vec)
    if db.execute("PRAGMA user_version").fetchone()[0] != SCHEMA_VERSION:
        init_schema(db)
    return db


# ── Wikitext → text ──────────────────────────────────────────────────────────
#
# Not a parser: templates are not expanded and the output is for reading and
# search, not for rendering. Good enough because only the words matter here.

_HEADING = re.compile(r"^(={1,6})\s*(.*?)\s*\1\s*$")
_COMMENT = re.compile(r"<!--.*?-->", re.S)
_REF = re.compile(r"<ref\b[^>/]*/>|<ref\b[^>]*>.*?</ref\s*>", re.S | re.I)
_CODE = re.compile(r"<(pre|source|syntaxhighlight|code)\b[^>]*>(.*?)</\1\s*>", re.S | re.I)
_MATH = re.compile(r"<math\b[^>]*>(.*?)</math\s*>", re.S | re.I)
_TEMPLATE = re.compile(r"\{\{([^{}]*)\}\}")
_FILE = re.compile(r"\[\[\s*(?:File|Image|Soubor|Obrázek)\s*:([^|\]]+)(?:\|[^\]]*)?\]\]", re.I)
_CATEGORY = re.compile(r"\[\[\s*(?:Category|Kategorie)\s*:[^\]]*\]\]", re.I)
_LINK = re.compile(r"\[\[([^|\]]*)(?:\|([^\]]*))?\]\]")
_EXTERNAL = re.compile(r"\[(?:https?:)?//[^\s\]]+\s+([^\]]+)\]|\[((?:https?:)?//[^\s\]]+)\]")
_TAG = re.compile(r"</?[A-Za-z][\w:-]*(?:\s[^>]*)?/?>")
_MAGIC = re.compile(r"__[A-Z]+__")
_PARAM = re.compile(r"^\s*([^=|]{1,40}?)\s*=\s*(.*)$", re.S)


def _template(match):
    """{{Name|a|k=v}} → 'a; k: v' — the name is markup, the values are prose."""
    parts = match.group(1).split("|")[1:]
    out = []
    for part in parts:
        named = _PARAM.match(part)
        value = (f"{named.group(1)}: {named.group(2).strip()}" if named else part).strip()
        if value and not value.endswith(":"):
            out.append(value)
    return " " + "; ".join(out) + " " if out else " "


def _table_line(line):
    """One line of a {| … |} table → text, or None to drop it."""
    stripped = line.strip()
    if stripped.startswith(("{|", "|}", "|-", "|+")):
        return "\n" if stripped.startswith("|-") else None
    if stripped[:1] in ("|", "!"):
        cells = re.split(r"\|\||!!", stripped[1:])
        # "style=… | text": a single pipe separates the attributes from the text.
        cells = [c.split("|", 1)[1] if "|" in c and "=" in c.split("|", 1)[0] else c for c in cells]
        return " | " + " | ".join(c.strip() for c in cells)
    return line


def wiki_text(source):
    """Wikitext (no headings) → readable text; code blocks become ``` fences."""
    fences = []

    def keep_code(m):
        fences.append(html.unescape(m.group(2)).strip("\n"))
        return f"\x00{len(fences) - 1}\x00"

    text = _COMMENT.sub("", source or "")
    text = _CODE.sub(keep_code, text)
    text = _REF.sub("", text)
    text = _MATH.sub(lambda m: " " + m.group(1).strip() + " ", text)
    previous = None
    while previous != text:   # innermost first, so nested templates unwind
        previous, text = text, _TEMPLATE.sub(_template, text)
    text = _FILE.sub(lambda m: f"[file {m.group(1).strip()}]", text)
    text = _CATEGORY.sub("", text)
    text = _LINK.sub(lambda m: (m.group(2) or m.group(1)).strip(), text)
    text = _EXTERNAL.sub(lambda m: m.group(1) or m.group(2), text)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = _TAG.sub("", text)
    text = _MAGIC.sub("", text)
    text = re.sub(r"'{2,}", "", text)

    lines = []
    in_table = 0
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("{|"):
            in_table += 1
        if in_table:
            converted = _table_line(line)
            if stripped.startswith("|}"):
                in_table -= 1
            if converted is not None:
                lines.append(converted)
            continue
        bullet = re.match(r"^([*#:;]+)\s*(.*)$", line)
        lines.append("- " + bullet.group(2) if bullet and bullet.group(1)[0] in "*#" else
                     (bullet.group(2) if bullet else line))
    text = html.unescape("\n".join(lines))
    text = re.sub(r"\x00(\d+)\x00", lambda m: f"\n```\n{fences[int(m.group(1))]}\n```\n", text)
    return _tidy(text)


def sections(source):
    """[(level, heading, text)] — level 0 is the text before the first heading."""
    out, level, heading, buf = [], 0, "", []

    def flush():
        out.append((level, heading, wiki_text("\n".join(buf))))
        buf.clear()

    in_code = False
    for line in (source or "").split("\n"):
        if re.search(r"<(pre|source|syntaxhighlight)\b", line, re.I):
            in_code = True
        if in_code and re.search(r"</(pre|source|syntaxhighlight)\s*>", line, re.I):
            in_code = False
            buf.append(line)
            continue
        h = None if in_code else _HEADING.match(line)
        if h:
            flush()
            level, heading = len(h.group(1)), wiki_text(h.group(2)).replace("\n", " ")
        else:
            buf.append(line)
    flush()
    return [s for s in out if s[1] or s[2]]


def _tidy(text):
    lines, fence = [], False
    for line in text.replace("\xa0", " ").split("\n"):
        if line.strip().startswith("```"):
            fence = not fence
            lines.append("```")
            continue
        lines.append(line.rstrip() if fence else re.sub(r"[ \t]+", " ", line).strip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def windows(text, size=CHUNK_CHARS, overlap=CHUNK_OVERLAP):
    text = text.strip()
    if len(text) <= size:
        return [text] if text else []
    out, start = [], 0
    while start < len(text):
        end = min(len(text), start + size)
        if end < len(text):
            cut = text.rfind("\n", start + size // 2, end)
            if cut < 0:
                cut = text.rfind(" ", start + size // 2, end)
            if cut > start:
                end = cut
        out.append(text[start:end].strip())
        if end >= len(text):
            break
        start = max(end - overlap, start + 1)
    return [w for w in out if w]


def chunk_page(page):
    """[(kind, heading path, text)] for one page."""
    out, path = [], {}
    for level, heading, text in sections(page["body"]):
        if level:
            path = {k: v for k, v in path.items() if k < level}
            path[level] = heading
        trail = " › ".join(v for _, v in sorted(path.items()) if v)
        for piece in windows(text):
            out.append(("section", trail, piece))
    if not out:
        out.append(("section", "", page["title"]))
    return out


# ── Writes from sync.sh (host) ───────────────────────────────────────────────

def cmd_init(args):
    init_schema(connect())


def cmd_put_pages(args):
    """Upsert pages from a query response (formatversion=2, prop=revisions|info|
    categories); print the ids whose content changed."""
    with open(args.response, encoding="utf-8") as fh:
        data = json.load(fh)
    namespaces = {}
    if args.namespaces:
        with open(args.namespaces, encoding="utf-8") as fh:
            namespaces = {int(k): v for k, v in json.load(fh).items()}
    db = open_db()
    fetched = now_utc()
    for item in (data.get("query") or {}).get("pages") or []:
        revisions = item.get("revisions") or []
        if item.get("missing") or item.get("invalid") or not revisions:
            continue   # sync.sh notices the revid did not arrive and asks again
        rev = revisions[0]
        slot = ((rev.get("slots") or {}).get("main") or {})
        if "content" not in slot:
            continue   # hidden revision, or content cut by the response size limit
        pid = str(item["pageid"])
        row = {
            "id": pid,
            "ns": int(item.get("ns") or 0),
            "ns_name": namespaces.get(int(item.get("ns") or 0)),
            "title": item.get("title") or "",
            "revid": int(rev.get("revid") or 0),
            "updated_at": to_utc(rev.get("timestamp")),
            "updated_by": rev.get("user"),
            "url": item.get("fullurl"),
            "categories": json.dumps(sorted(c["title"].split(":", 1)[-1] for c in item.get("categories") or []),
                                     ensure_ascii=False),
            "body": slot.get("content") or "",
            "fetched_at": fetched,
        }
        old = db.execute("SELECT title, revid, body FROM pages WHERE id = ?", (pid,)).fetchone()
        changed = old is None or (old["title"], old["revid"], old["body"]) != (row["title"], row["revid"], row["body"])
        db.execute(
            """INSERT INTO pages (id, ns, ns_name, title, revid, updated_at, updated_by, url,
                                  categories, body, fetched_at, indexed)
               VALUES (:id, :ns, :ns_name, :title, :revid, :updated_at, :updated_by, :url,
                       :categories, :body, :fetched_at, 0)
               ON CONFLICT (id) DO UPDATE SET
                 ns = excluded.ns, ns_name = excluded.ns_name, title = excluded.title,
                 revid = excluded.revid, updated_at = excluded.updated_at,
                 updated_by = excluded.updated_by, url = excluded.url,
                 categories = excluded.categories, body = excluded.body,
                 fetched_at = excluded.fetched_at""",
            row,
        )
        if changed:
            db.execute("UPDATE pages SET indexed = 0 WHERE id = ?", (pid,))
            print(pid)
    db.commit()


def _wanted():
    """'<pageid> <revid>' lines on stdin → {pageid: revid}."""
    wanted = {}
    for line in sys.stdin:
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            wanted[parts[0]] = int(parts[1])
    return wanted


def cmd_plan(args):
    """Print the ids from stdin whose revid differs from the stored one."""
    wanted = _wanted()
    have = {r["id"]: r["revid"] for r in open_db().execute("SELECT id, revid FROM pages")}
    for pid, revid in wanted.items():
        if have.get(pid) != revid:
            print(pid)


def cmd_prune(args):
    """Delete every page whose id is not on stdin; print the ids removed."""
    keep = _wanted()
    db = open_db()
    gone = [r["id"] for r in db.execute("SELECT id FROM pages") if r["id"] not in keep]
    for pid in gone:
        db.execute("DELETE FROM pages WHERE id = ?", (pid,))
        print(pid)
    db.commit()


# ── Navigation map (host) ────────────────────────────────────────────────────

def cmd_nav_map(args):
    """The page list of navigation_map.md. Changed ids on stdin are marked ★."""
    hot = {line.strip() for line in sys.stdin if line.strip()}
    db = open_db()
    rows = db.execute("SELECT id, ns, ns_name, title, revid, updated_at, updated_by, categories, indexed "
                      "FROM pages ORDER BY ns, title").fetchall()
    if not rows:
        print("_Nothing pulled yet._")
        return
    pending = sum(1 for r in rows if not r["indexed"])
    print("Pages live in `.wiki/.db/wiki.db`, not in files. Read one with "
          "`.wiki/kb.sh page <id or title>`; search with `.wiki/kb.sh search \"<question>\"`.")
    if pending:
        print(f"{pending} page(s) changed since the last `kb.sh index`.")
    print()
    by_ns = {}
    for r in rows:
        by_ns.setdefault(r["ns"], []).append(r)
    for ns, pages in by_ns.items():
        name = pages[0]["ns_name"] or ("(main)" if ns == 0 else f"namespace {ns}")
        print(f"### {name} — {len(pages)} page{'s' if len(pages) != 1 else ''}\n")
        for r in pages:
            cats = json.loads(r["categories"])
            extra = f" — {', '.join(cats)}" if cats else ""
            star = " ★" if r["id"] in hot else ""
            print(f"- {r['title']} — `{r['id']}` r{r['revid']}, {(r['updated_at'] or '')[:10]}, "
                  f"{r['updated_by'] or '?'}{extra}{star}")
        print()


# ── Readers ──────────────────────────────────────────────────────────────────

def _find_page(db, key):
    page = db.execute("SELECT * FROM pages WHERE id = ?", (key,)).fetchone()
    if page is None:
        title = key.replace("_", " ").strip()
        page = db.execute("SELECT * FROM pages WHERE title = ? COLLATE NOCASE", (title,)).fetchone()
    return page


def cmd_page(args):
    db = open_db()
    key = " ".join(args.id)
    page = _find_page(db, key)
    if not page:
        die(f"no page '{key}' in the mirror", 2)
    if args.source:
        print(page["body"])
        return
    cats = ", ".join(json.loads(page["categories"]))
    print(f"# {page['title']}\n")
    print(f"page {page['id']} · r{page['revid']} · updated {page['updated_at']}"
          f" by {page['updated_by'] or '?'}{' · indexed' if page['indexed'] else ' · not indexed'}")
    if cats:
        print(f"categories: {cats}")
    print(f"{page['url'] or ''}\n")
    for level, heading, text in sections(page["body"]):
        if level:
            print("#" * min(6, level) + " " + heading + "\n")
        if text:
            print(text + "\n")


def cmd_status(args):
    db = open_db()
    total = db.execute("SELECT count(*) FROM pages").fetchone()[0]
    pending = db.execute("SELECT count(*) FROM pages WHERE indexed = 0").fetchone()[0]
    chunks = db.execute("SELECT count(*) FROM chunks").fetchone()[0]
    newest = db.execute("SELECT max(updated_at), max(fetched_at), max(indexed_at) FROM pages").fetchone()
    print(f"database   {os.environ['KB_DB']}  ({os.path.getsize(os.environ['KB_DB']) // 1024} KiB)")
    for r in db.execute("SELECT ns, ns_name, count(*) AS n FROM pages GROUP BY ns ORDER BY ns"):
        print(f"namespace  {r['ns_name'] or '(main)' if r['ns'] == 0 else r['ns_name'] or r['ns']}: {r['n']} pages")
    print(f"pages      {total}, indexed {total - pending}, not indexed {pending}")
    print(f"chunks     {chunks}")
    print(f"newest     page update {newest[0]}, last fetch {newest[1]}, last index {newest[2]}")


def _fts_query(text):
    words = [w for w in re.findall(r"\w+", text, re.UNICODE) if len(w) > 1]
    return " OR ".join('"' + w.replace('"', '') + '"' for w in words)


def _keyword_hits(db, query, limit):
    match = _fts_query(query)
    if not match:
        return []
    return [r[0] for r in db.execute(
        "SELECT rowid FROM chunks WHERE chunks MATCH ? ORDER BY bm25(chunks, 2.0, 1.0) LIMIT ?",
        (match, limit))]


def _print_hits(db, ranked, limit, query):
    pending = db.execute("SELECT count(*) FROM pages WHERE indexed = 0").fetchone()[0]
    if not db.execute("SELECT count(*) FROM chunks").fetchone()[0]:
        die("nothing indexed yet: run .wiki/kb.sh index", 3)
    if pending:
        print(f"note: {pending} page(s) changed since the last index; run .wiki/kb.sh index\n")
    shown, seen = 0, set()
    for rowid, score, sources in ranked:
        row = db.execute(
            """SELECT c.heading, c.text, c.page_id, c.kind, p.title, p.updated_at
               FROM chunks c JOIN pages p ON p.id = c.page_id WHERE c.rowid = ?""", (rowid,)).fetchone()
        if not row or (row["page_id"], row["heading"]) in seen:
            continue
        seen.add((row["page_id"], row["heading"]))
        shown += 1
        snippet = re.sub(r"\s+", " ", row["text"])[:300]
        print(f"{shown}. {row['heading'] or row['title']}")   # the heading starts with the title
        print(f"   page {row['page_id']} · updated {row['updated_at'][:10]} · {sources} · score {score:.4f}")
        print(f"   {snippet}\n")
        if shown >= limit:
            break
    if not shown:
        print(f"no match for: {query}")


def cmd_search(args, model=None):
    query = " ".join(args.query)
    db = open_db(vec=not args.keyword)
    kw = _keyword_hits(db, query, CANDIDATES)
    if args.keyword:
        _print_hits(db, [(r, 1.0 / (RRF_K + i), "keyword") for i, r in enumerate(kw)], args.limit, query)
        return
    vec = [r[0] for r in db.execute(
        "SELECT rowid FROM chunks_vec WHERE embedding MATCH ? AND k = ? ORDER BY distance",
        ((model or Embedder()).embed([f"query: {query}"])[0].tobytes(), CANDIDATES))] if _has_vec(db) else []
    scores, sources = {}, {}
    for name, hits in (("keyword", kw), ("meaning", vec)):
        for i, rowid in enumerate(hits):
            scores[rowid] = scores.get(rowid, 0.0) + 1.0 / (RRF_K + i + 1)
            sources.setdefault(rowid, []).append(f"{name} #{i + 1}")
    ranked = sorted(scores, key=scores.get, reverse=True)
    _print_hits(db, [(r, scores[r], ", ".join(sources[r])) for r in ranked], args.limit, query)


# ── Index (container) ────────────────────────────────────────────────────────

class Embedder:
    """multilingual-e5-small, ONNX, mean-pooled and L2-normalised. Inputs take
    the model's prefixes: "query: …" for questions, "passage: …" for text."""

    def __init__(self):
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        model_dir = os.environ.get("KB_MODEL_DIR", "/model")
        self.np = np
        self.tok = Tokenizer.from_file(os.path.join(model_dir, "tokenizer.json"))
        self.tok.enable_truncation(512)
        self.tok.enable_padding()
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        self.session = ort.InferenceSession(os.path.join(model_dir, "model.onnx"), opts,
                                            providers=["CPUExecutionProvider"])
        self.inputs = {i.name for i in self.session.get_inputs()}

    def embed(self, texts, batch=32):
        np = self.np
        out = []
        for start in range(0, len(texts), batch):
            enc = self.tok.encode_batch(texts[start:start + batch])
            ids = np.array([e.ids for e in enc], dtype=np.int64)
            mask = np.array([e.attention_mask for e in enc], dtype=np.int64)
            feed = {"input_ids": ids, "attention_mask": mask}
            if "token_type_ids" in self.inputs:
                feed["token_type_ids"] = np.zeros_like(ids)
            hidden = self.session.run(None, feed)[0]
            summed = (hidden * mask[:, :, None]).sum(axis=1)
            pooled = summed / np.clip(mask.sum(axis=1, keepdims=True), 1, None)
            pooled /= np.clip(np.linalg.norm(pooled, axis=1, keepdims=True), 1e-12, None)
            out.extend(pooled.astype(np.float32))
        return out


def _has_vec(db):
    return db.execute("SELECT 1 FROM sqlite_master WHERE name = 'chunks_vec'").fetchone() is not None


def cmd_index(args, model=None):
    db = open_db(vec=True)
    db.execute(f"CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(embedding float[{EMBED_DIM}])")

    # Chunks of pages that left the mirror.
    orphans = [r[0] for r in db.execute(
        "SELECT rowid FROM chunks WHERE page_id NOT IN (SELECT id FROM pages)")]
    for rowid in orphans:
        db.execute("DELETE FROM chunks WHERE rowid = ?", (rowid,))
        db.execute("DELETE FROM chunks_vec WHERE rowid = ?", (rowid,))
    db.commit()

    where = "" if args.all else "WHERE indexed = 0"
    todo = db.execute(f"SELECT id, title, revid, body FROM pages {where} ORDER BY id").fetchall()
    if not todo:
        print(f"index: up to date ({len(orphans)} stale chunk(s) removed)" if orphans else "index: up to date")
        return
    print(f"index: {len(todo)} page(s)", file=sys.stderr)
    model = model or Embedder()
    total = 0
    for n, page in enumerate(todo, 1):
        pieces = chunk_page(page)
        vectors = model.embed([f"passage: {page['title']} › {h}\n{t}" if h else f"passage: {page['title']}\n{t}"
                               for _, h, t in pieces])
        old = [r[0] for r in db.execute("SELECT rowid FROM chunks WHERE page_id = ?", (page["id"],))]
        for rowid in old:
            db.execute("DELETE FROM chunks_vec WHERE rowid = ?", (rowid,))
        db.execute("DELETE FROM chunks WHERE page_id = ?", (page["id"],))
        for ord_, ((kind, heading, text), vector) in enumerate(zip(pieces, vectors)):
            cur = db.execute("INSERT INTO chunks (heading, text, page_id, ord, kind) VALUES (?, ?, ?, ?, ?)",
                             (f"{page['title']} › {heading}" if heading else page["title"], text,
                              page["id"], ord_, kind))
            db.execute("INSERT INTO chunks_vec (rowid, embedding) VALUES (?, ?)",
                       (cur.lastrowid, vector.tobytes()))
        # Only if sync.sh did not change the page meanwhile.
        db.execute("UPDATE pages SET indexed = 1, indexed_at = ? WHERE id = ? AND revid = ?",
                   (now_utc(), page["id"], page["revid"]))
        db.commit()
        total += len(pieces)
        if n % 50 == 0:
            print(f"index: {n}/{len(todo)} pages", file=sys.stderr)
    print(f"index: {len(todo)} page(s), {total} chunk(s) embedded")


# ── Server (container) and its client (host) ─────────────────────────────────
#
# One request per connection: the client sends {"argv": [...]} and closes its
# side; the server runs that command with the loaded model, capturing what it
# prints, and answers {"code", "out", "err"}. Requests run one at a time.

def cmd_ping(args, model=None):
    print("kb: server ready")


def _run_captured(argv, model):
    out, err, code = io.StringIO(), io.StringIO(), 0
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            args = build_parser().parse_args(argv)
            if args.cmd not in SERVED or getattr(args, "keyword", False):
                die(f"the server does not run '{args.cmd}'", 64)
            globals()["cmd_" + args.cmd](args, model)
        except SystemExit as stop:
            code = stop.code if isinstance(stop.code, int) else (0 if stop.code is None else 1)
        except Exception:   # a bad request must not take the server down
            traceback.print_exc()
            code = 70
    return {"code": code, "out": out.getvalue(), "err": err.getvalue()}


def cmd_serve(args):
    model = Embedder()
    path = args.socket
    with contextlib.suppress(FileNotFoundError):
        os.unlink(path)   # left by a server that was killed
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    os.chmod(path, 0o600)
    server.listen(8)
    server.settimeout(args.idle if args.idle > 0 else None)   # 0: never exit idle

    def stop(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)   # PID 1 in a container ignores SIGTERM without a handler
    signal.signal(signal.SIGINT, stop)
    print(f"kb: serving on {path}" + (f", exiting after {args.idle} s idle" if args.idle > 0 else ""),
          file=sys.stderr, flush=True)
    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                print("kb: idle, exiting", file=sys.stderr, flush=True)
                return
            with conn:
                conn.settimeout(30)
                try:
                    raw = b""
                    while chunk := conn.recv(65536):
                        raw += chunk
                    reply = _run_captured(json.loads(raw)["argv"], model)
                except (OSError, ValueError, KeyError, TypeError) as error:
                    reply = {"code": 64, "out": "", "err": f"kb: bad request: {error}\n"}
                conn.settimeout(None)
                with contextlib.suppress(OSError):
                    conn.sendall(json.dumps(reply).encode())
    finally:
        server.close()
        with contextlib.suppress(FileNotFoundError):
            os.unlink(path)


def remote(path, argv):
    """Run argv on the server at path; exits with its code, or EX_NO_SERVER."""
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(path)
    except OSError:
        sys.exit(EX_NO_SERVER)
    with client:
        client.sendall(json.dumps({"argv": argv}).encode())
        client.shutdown(socket.SHUT_WR)
        raw = b""
        while chunk := client.recv(65536):
            raw += chunk
    if not raw:
        sys.exit(EX_NO_SERVER)   # it exited (idle) between accept and answer
    reply = json.loads(raw)
    sys.stdout.write(reply["out"])
    sys.stderr.write(reply["err"])
    sys.exit(reply["code"])


# ── CLI ──────────────────────────────────────────────────────────────────────

def build_parser():
    p = argparse.ArgumentParser(prog="kb.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init")
    s = sub.add_parser("put-pages"); s.add_argument("response"); s.add_argument("--namespaces")
    sub.add_parser("plan")
    sub.add_parser("prune")
    sub.add_parser("nav-map")
    s = sub.add_parser("page"); s.add_argument("id", nargs="+"); s.add_argument("--source", action="store_true")
    sub.add_parser("status")
    s = sub.add_parser("search"); s.add_argument("query", nargs="+")
    s.add_argument("--limit", type=int, default=10); s.add_argument("--keyword", action="store_true")
    s = sub.add_parser("index"); s.add_argument("--all", action="store_true")
    sub.add_parser("ping")
    s = sub.add_parser("serve"); s.add_argument("--socket", default="/tmp/kb.sock")
    s.add_argument("--idle", type=int, default=1800, help="seconds without a request before exiting; 0: never")
    return p


def main():
    args = build_parser().parse_args()
    if os.environ.get("KB_SOCKET") and args.cmd in SERVED and not getattr(args, "keyword", False):
        remote(os.environ["KB_SOCKET"], sys.argv[1:])
    handler = globals()["cmd_" + args.cmd.replace("-", "_")]
    try:
        handler(args)
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()
