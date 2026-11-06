#!/usr/bin/env python3
"""kb.py — the Confluence mirror as one SQLite file, with keyword and vector search.

One file, two halves:

  host, standard library only
      sync.sh stores what it downloads here: init, put-pages, put-comments,
      drop-comments, versions, stamps, prune, import-files, nav-map.
      Readers: page, status, search --keyword.
  container (the jo-confluence-kb image, docker/confluence/: model +
  onnxruntime + sqlite-vec, no network; this file is mounted over /app/kb.py)
      index    pages whose `indexed` flag is 0 → sections → chunks, FTS5 rows
               and embeddings; then the flag goes to 1
      search   keyword and vector hits fused into one ranking
      serve    keep the model loaded and answer search / index over a Unix
               socket; exits after --idle seconds without a request. The host
               side reaches it when $KB_SOCKET is set (kb.sh sets it).

The database: $KB_DB (sync.sh and kb.sh set it to .atlassian/.db/confluence.db).

  pages          one row per page: version, updated_at (UTC timestamp), the
                 storage-format source, and `indexed` (0/1): 0 whenever the
                 page or its comments changed, 1 once chunks and vectors match
  comments       the page's comments, storage format
  chunks         FTS5: one row per section window or comment
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
    id            TEXT PRIMARY KEY,
    space         TEXT NOT NULL,
    space_name    TEXT,
    title         TEXT NOT NULL,
    version       INTEGER NOT NULL,
    updated_at    TEXT NOT NULL,              -- last update on the server, UTC, ISO 8601
    updated_by    TEXT,
    url           TEXT,
    ancestors     TEXT NOT NULL DEFAULT '[]', -- JSON [{id, title}], root first
    body          TEXT NOT NULL,              -- storage-format XHTML, as served
    comment_stamp TEXT,                       -- "<comment id>.<version> …" when last fetched
    indexed       INTEGER NOT NULL DEFAULT 0 CHECK (indexed IN (0, 1)),
    indexed_at    TEXT,
    fetched_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS pages_space ON pages (space);
CREATE INDEX IF NOT EXISTS pages_pending ON pages (indexed);
CREATE TABLE IF NOT EXISTS comments (
    id       TEXT PRIMARY KEY,
    page_id  TEXT NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    ord      INTEGER NOT NULL,
    author   TEXT,
    created  TEXT,
    body     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS comments_page ON comments (page_id, ord);
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
    """Confluence's '2026-10-27T16:54:40.553+01:00' → '2026-10-27T15:54:40Z'."""
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
    db.execute("PRAGMA foreign_keys = ON")
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


# ── Storage XHTML → text ─────────────────────────────────────────────────────
#
# Confluence keeps code as <![CDATA[…]]> and wraps everything in ac:/ri: tags.
# A regex tokenizer that knows CDATA, comments, script and style is enough:
# the source is machine-written, and nothing here needs a full DOM.

_TOKEN = re.compile(
    r"<!\[CDATA\[(?P<cdata>.*?)\]\]>"
    r"|<!--.*?-->"
    r"|<(?P<raw>script|style)\b[^>]*>.*?</(?P=raw)\s*>"
    r"|<(?P<close>/?)(?P<tag>[A-Za-z][\w:.-]*)(?P<attrs>(?:[^>\"']|\"[^\"]*\"|'[^']*')*)>",
    re.S | re.I,
)
_ATTR = re.compile(r"([\w:.-]+)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')")
_HEADING = re.compile(r"h([1-6])$", re.I)
_BLOCK = {
    "p", "div", "br", "ul", "ol", "table", "tbody", "thead", "tr", "pre",
    "blockquote", "hr", "ac:layout", "ac:layout-section", "ac:layout-cell",
    "ac:structured-macro", "ac:rich-text-body", "ac:task-list", "ac:task",
}
_KEPT_PARAMETERS = {"key", "title"}   # a Jira key or a panel title is prose; the rest is config


def _attrs(text):
    return {m.group(1).lower(): html.unescape(m.group(2) if m.group(2) is not None else m.group(3))
            for m in _ATTR.finditer(text or "")}


def sections(storage):
    """[(level, heading, text)] — level 0 is the text before the first heading."""
    out = []
    level, heading = 0, ""
    buf, head_buf = [], None
    skip_parameter = False
    in_code_body = False

    def emit(text):
        if head_buf is not None:
            head_buf.append(text)
        elif not skip_parameter:
            buf.append(text)

    def flush():
        out.append((level, heading, _tidy("".join(buf))))
        buf.clear()

    pos = 0
    for m in _TOKEN.finditer(storage or ""):
        if m.start() > pos:
            emit(html.unescape(storage[pos:m.start()]))
        pos = m.end()
        if m.group("cdata") is not None:
            code = m.group("cdata")
            emit(f"\n```\n{code}\n```\n" if in_code_body else code)
            continue
        tag = (m.group("tag") or "").lower()
        if not tag:
            continue  # a comment, script or style
        closing = m.group("close") == "/"
        h = _HEADING.match(tag)
        if h:
            if not closing:
                flush()
                level, head_buf = int(h.group(1)), []
            elif head_buf is not None:
                heading = _tidy(" ".join(head_buf)).replace("\n", " ")
                head_buf = None
            continue
        if tag == "ac:parameter":
            if closing:
                skip_parameter = False
            elif _attrs(m.group("attrs")).get("ac:name") not in _KEPT_PARAMETERS:
                skip_parameter = True
            continue
        if tag == "ac:plain-text-body":
            in_code_body = not closing
            continue
        if not closing and tag in ("ri:page", "ri:content-entity", "ri:blog-post"):
            title = _attrs(m.group("attrs")).get("ri:content-title")
            if title:
                emit(title)
            continue
        if not closing and tag == "ri:attachment":
            name = _attrs(m.group("attrs")).get("ri:filename")
            if name:
                emit(f"[file {name}]")
            continue
        if not closing and tag == "li":
            emit("\n- ")
        elif not closing and tag in ("td", "th"):
            emit(" | ")
        elif tag in _BLOCK:
            emit("\n")
    if pos < len(storage or ""):
        emit(html.unescape(storage[pos:]))
    if head_buf is not None:   # an unclosed heading: keep its words as text
        buf.extend(head_buf)
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


def chunk_page(page, comments):
    """[(kind, heading path, text)] for one page and its comments."""
    out, path = [], {}
    for level, heading, text in sections(page["body"]):
        if level:
            path = {k: v for k, v in path.items() if k < level}
            path[level] = heading
        trail = " › ".join(v for _, v in sorted(path.items()) if v)
        for piece in windows(text):
            out.append(("section", trail, piece))
    for c in comments:
        text = "\n\n".join(s[2] for s in sections(c["body"]) if s[2])
        label = f"comment by {c['author'] or '?'}, {(c['created'] or '')[:10]}"
        for piece in windows(text):
            out.append(("comment", label, piece))
    if not out:
        out.append(("section", "", page["title"]))
    return out


# ── Writes from sync.sh (host) ───────────────────────────────────────────────

def _load_results(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return data.get("results", []) if isinstance(data, dict) else []


def cmd_init(args):
    init_schema(connect())


def cmd_put_pages(args):
    """Upsert pages from a content response; print the ids whose content changed."""
    db = open_db()
    wanted = set(args.ids)
    fetched = now_utc()
    for item in _load_results(args.response):
        pid = str(item.get("id", ""))
        if not pid.isdigit() or (wanted and pid not in wanted):
            continue
        space = item.get("space") or {}
        version = item.get("version") or {}
        links = item.get("_links") or {}
        row = {
            "id": pid,
            "space": space.get("key") or "",
            "space_name": space.get("name"),
            "title": item.get("title") or "",
            "version": int(version.get("number") or 0),
            "updated_at": to_utc(version.get("when")),
            "updated_by": (version.get("by") or {}).get("displayName"),
            "url": (links.get("base") or "") + (links.get("webui") or ""),
            "ancestors": json.dumps([{"id": str(a.get("id")), "title": a.get("title")}
                                     for a in item.get("ancestors") or []], ensure_ascii=False),
            "body": ((item.get("body") or {}).get("storage") or {}).get("value") or "",
            "fetched_at": fetched,
        }
        old = db.execute("SELECT title, version, body, ancestors FROM pages WHERE id = ?",
                         (pid,)).fetchone()
        changed = old is None or (old["title"], old["version"], old["body"], old["ancestors"]) != (
            row["title"], row["version"], row["body"], row["ancestors"])
        db.execute(
            """INSERT INTO pages (id, space, space_name, title, version, updated_at, updated_by,
                                  url, ancestors, body, fetched_at, indexed)
               VALUES (:id, :space, :space_name, :title, :version, :updated_at, :updated_by,
                       :url, :ancestors, :body, :fetched_at, 0)
               ON CONFLICT (id) DO UPDATE SET
                 space = excluded.space, space_name = excluded.space_name,
                 title = excluded.title, version = excluded.version,
                 updated_at = excluded.updated_at, updated_by = excluded.updated_by,
                 url = excluded.url, ancestors = excluded.ancestors, body = excluded.body,
                 fetched_at = excluded.fetched_at""",
            row,
        )
        if changed:
            db.execute("UPDATE pages SET indexed = 0 WHERE id = ?", (pid,))
            print(pid)
    db.commit()


def _replace_comments(db, pid, rows, stamp):
    old = [tuple(r) for r in db.execute(
        "SELECT id, author, created, body FROM comments WHERE page_id = ? ORDER BY ord", (pid,))]
    new = [(r["id"], r["author"], r["created"], r["body"]) for r in rows]
    db.execute("UPDATE pages SET comment_stamp = ? WHERE id = ?", (stamp or None, pid))
    if old == new:
        return False
    db.execute("DELETE FROM comments WHERE page_id = ?", (pid,))
    db.executemany(
        "INSERT INTO comments (id, page_id, ord, author, created, body) VALUES (?, ?, ?, ?, ?, ?)",
        [(c[0], pid, i, c[1], c[2], c[3]) for i, c in enumerate(new)])
    db.execute("UPDATE pages SET indexed = 0 WHERE id = ?", (pid,))
    return True


def cmd_put_comments(args):
    """Replace a page's comments from a child/comment response; print the id if they changed."""
    db = open_db()
    if not db.execute("SELECT 1 FROM pages WHERE id = ?", (args.id,)).fetchone():
        return
    rows = [{"id": str(c.get("id")),
             "author": ((c.get("history") or {}).get("createdBy") or {}).get("displayName"),
             "created": to_utc((c.get("history") or {}).get("createdDate")),
             "body": ((c.get("body") or {}).get("storage") or {}).get("value") or ""}
            for c in _load_results(args.response)]
    if _replace_comments(db, args.id, rows, args.stamp):
        print(args.id)
    db.commit()


def cmd_drop_comments(args):
    db = open_db()
    if db.execute("SELECT 1 FROM pages WHERE id = ?", (args.id,)).fetchone() and \
            _replace_comments(db, args.id, [], None):
        print(args.id)
    db.commit()


def cmd_versions(args):
    for r in open_db().execute("SELECT id, version FROM pages"):
        print(r["id"], r["version"])


def cmd_stamps(args):
    for r in open_db().execute("SELECT id, comment_stamp FROM pages WHERE comment_stamp IS NOT NULL"):
        print(r["id"], r["comment_stamp"])


def cmd_prune(args):
    """Delete every page whose id is not on stdin; print the ids removed."""
    keep = {line.strip() for line in sys.stdin if line.strip()}
    db = open_db()
    gone = [r["id"] for r in db.execute("SELECT id FROM pages") if r["id"] not in keep]
    for pid in gone:
        db.execute("DELETE FROM pages WHERE id = ?", (pid,))   # comments cascade
        print(pid)
    db.commit()


_COMMENT_HEAD = re.compile(r"^<h2>(?P<author>.*) — (?P<date>\d{4}-\d{2}-\d{2}) — comment (?P<id>\w+)</h2>$")


def cmd_import_files(args):
    """One-off: load the per-file mirror (.confluence/<SPACE>/<id>.html + cache
    meta) into the database. No network. Prints the ids imported."""
    db = open_db()
    fetched = now_utc()
    meta_dir = args.cache_dir
    for name in sorted(os.listdir(meta_dir)):
        if not re.fullmatch(r"\d+\.json", name):
            continue
        pid = name[:-5]
        with open(os.path.join(meta_dir, name), encoding="utf-8") as fh:
            meta = json.load(fh)
        page_file = os.path.join(args.confluence_dir, meta.get("space", ""), f"{pid}.html")
        if not os.path.isfile(page_file):
            continue
        with open(page_file, encoding="utf-8") as fh:
            raw = fh.read()
        parts = raw.split("\n", 2)   # header comment, <h1>title</h1>, body
        body = parts[2][:-1] if len(parts) == 3 and parts[2].endswith("\n") else (parts[2] if len(parts) == 3 else "")
        db.execute(
            """INSERT OR REPLACE INTO pages (id, space, space_name, title, version, updated_at,
                   updated_by, url, ancestors, body, fetched_at, indexed)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)""",
            (pid, meta.get("space", ""), meta.get("space_name"), meta.get("title", ""),
             int(meta.get("version") or 0), to_utc(meta.get("updated")), meta.get("by"),
             meta.get("url"), json.dumps(meta.get("ancestors") or [], ensure_ascii=False), body,
             fetched))
        stamp_file = os.path.join(meta_dir, f"{pid}.comments.stamp")
        stamp = None
        if os.path.isfile(stamp_file):
            with open(stamp_file, encoding="utf-8") as fh:
                stamp = fh.read().strip() or None
        comments_file = os.path.join(args.confluence_dir, meta.get("space", ""), f"{pid}.comments.html")
        rows = []
        if os.path.isfile(comments_file):
            with open(comments_file, encoding="utf-8") as fh:
                lines = fh.read().split("\n")[1:]
            current = None
            for line in lines:
                head = _COMMENT_HEAD.match(line)
                if head:
                    current = {"id": head["id"], "author": html.unescape(head["author"]),
                               "created": head["date"] + "T00:00:00Z", "body": []}
                    rows.append(current)
                elif current is not None:
                    current["body"].append(line)
            for r in rows:
                r["body"] = "\n".join(r["body"]).strip("\n")
        _replace_comments(db, pid, rows, stamp)
        print(pid)
    db.commit()


# ── Navigation map (host) ────────────────────────────────────────────────────

def cmd_nav_map(args):
    """The Confluence part of navigation_map.md. Change labels on stdin
    ("confluence:<id>[:…]") mark pages ★."""
    hot = set()
    for line in sys.stdin:
        m = re.match(r"confluence:(\d+)", line.strip())
        if m:
            hot.add(m.group(1))
    db = open_db()
    rows = db.execute(
        """SELECT p.id, p.space, p.space_name, p.title, p.version, p.updated_at, p.updated_by,
                  p.ancestors, p.indexed, (SELECT count(*) FROM comments c WHERE c.page_id = p.id) AS ncomments
           FROM pages p""").fetchall()
    if not rows:
        print("_Nothing pulled yet._")
        return
    have = {r["id"] for r in rows}
    pending = sum(1 for r in rows if not r["indexed"])
    print("Pages live in `.atlassian/.db/confluence.db`, not in files. Read one with "
          "`.atlassian/kb.sh page <id>`; search with `.atlassian/kb.sh search \"<question>\"`.")
    if pending:
        print(f"{pending} page(s) changed since the last `kb.sh index`.")
    print()
    by_space = {}
    for r in rows:
        by_space.setdefault(r["space"], []).append(r)
    for space in sorted(by_space):
        pages = by_space[space]
        print(f"### {space} — {pages[0]['space_name'] or space} — {len(pages)} page{'s' if len(pages) != 1 else ''}\n")

        def key(r):
            return [a["title"] or "" for a in json.loads(r["ancestors"])] + [r["title"]]
        for r in sorted(pages, key=key):
            anc = json.loads(r["ancestors"])
            depth = sum(1 for a in anc if a["id"] in have)
            orphan = depth == 0 and anc
            if orphan:
                print("- _" + " / ".join(a["title"] or "" for a in anc) + "_")
            pad = "  " * (depth + (1 if orphan else 0))
            extra = f", {r['ncomments']} comment{'s' if r['ncomments'] != 1 else ''}" if r["ncomments"] else ""
            star = " ★" if r["id"] in hot else ""
            print(f"{pad}- {r['title']} — `{r['id']}` v{r['version']}, {(r['updated_at'] or '')[:10]}, "
                  f"{r['updated_by'] or '?'}{extra}{star}")
        print()


# ── Readers ──────────────────────────────────────────────────────────────────

def cmd_page(args):
    db = open_db()
    page = db.execute("SELECT * FROM pages WHERE id = ?", (args.id,)).fetchone()
    if not page:
        die(f"no page {args.id} in the mirror", 2)
    if args.source:
        print(page["body"])
        return
    anc = " / ".join(a["title"] or "" for a in json.loads(page["ancestors"]))
    print(f"# {page['title']}\n")
    print(f"page {page['id']} · space {page['space']} · v{page['version']} · updated {page['updated_at']}"
          f" by {page['updated_by'] or '?'}{' · indexed' if page['indexed'] else ' · not indexed'}")
    if anc:
        print(f"under: {anc}")
    print(f"{page['url']}\n")
    for level, heading, text in sections(page["body"]):
        if level:
            print("#" * min(6, level + 1) + " " + heading + "\n")
        if text:
            print(text + "\n")
    comments = db.execute("SELECT * FROM comments WHERE page_id = ? ORDER BY ord", (args.id,)).fetchall()
    if comments:
        print("## Comments\n")
        for c in comments:
            text = "\n\n".join(s[2] for s in sections(c["body"]) if s[2])
            print(f"### {c['author'] or '?'} — {(c['created'] or '')[:10]}\n\n{text}\n")


def cmd_status(args):
    db = open_db()
    total = db.execute("SELECT count(*) FROM pages").fetchone()[0]
    pending = db.execute("SELECT count(*) FROM pages WHERE indexed = 0").fetchone()[0]
    chunks = db.execute("SELECT count(*) FROM chunks").fetchone()[0]
    ncomments = db.execute("SELECT count(*) FROM comments").fetchone()[0]
    newest = db.execute("SELECT max(updated_at), max(fetched_at), max(indexed_at) FROM pages").fetchone()
    print(f"database   {os.environ['KB_DB']}  ({os.path.getsize(os.environ['KB_DB']) // 1024} KiB)")
    for r in db.execute("SELECT space, count(*) AS n FROM pages GROUP BY space ORDER BY space"):
        print(f"space      {r['space']}: {r['n']} pages")
    print(f"pages      {total}, indexed {total - pending}, not indexed {pending}")
    print(f"comments   {ncomments}")
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
        die("nothing indexed yet: run .atlassian/kb.sh index", 3)
    if pending:
        print(f"note: {pending} page(s) changed since the last index; run .atlassian/kb.sh index\n")
    shown, seen = 0, set()
    for rowid, score, sources in ranked:
        row = db.execute(
            """SELECT c.heading, c.text, c.page_id, c.kind, p.title, p.space, p.updated_at
               FROM chunks c JOIN pages p ON p.id = c.page_id WHERE c.rowid = ?""", (rowid,)).fetchone()
        if not row or (row["page_id"], row["heading"]) in seen:
            continue
        seen.add((row["page_id"], row["heading"]))
        shown += 1
        snippet = re.sub(r"\s+", " ", row["text"])[:300]
        print(f"{shown}. {row['heading'] or row['title']}")   # the heading starts with the title
        print(f"   page {row['page_id']} · {row['space']} · {row['kind']} · updated {row['updated_at'][:10]}"
              f" · {sources} · score {score:.4f}")
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
    todo = db.execute(f"SELECT id, title, version, body FROM pages {where} ORDER BY id").fetchall()
    if not todo:
        print(f"index: up to date ({len(orphans)} stale chunk(s) removed)" if orphans else "index: up to date")
        return
    print(f"index: {len(todo)} page(s)", file=sys.stderr)
    model = model or Embedder()
    total = 0
    for n, page in enumerate(todo, 1):
        comments = db.execute("SELECT author, created, body FROM comments WHERE page_id = ? ORDER BY ord",
                              (page["id"],)).fetchall()
        pieces = chunk_page(page, comments)
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
        db.execute("UPDATE pages SET indexed = 1, indexed_at = ? WHERE id = ? AND version = ?",
                   (now_utc(), page["id"], page["version"]))
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
    s = sub.add_parser("put-pages"); s.add_argument("response"); s.add_argument("ids", nargs="*")
    s = sub.add_parser("put-comments"); s.add_argument("id"); s.add_argument("response"); s.add_argument("stamp", nargs="?", default="")
    s = sub.add_parser("drop-comments"); s.add_argument("id")
    sub.add_parser("versions")
    sub.add_parser("stamps")
    sub.add_parser("prune")
    s = sub.add_parser("import-files"); s.add_argument("confluence_dir"); s.add_argument("cache_dir")
    sub.add_parser("nav-map")
    s = sub.add_parser("page"); s.add_argument("id"); s.add_argument("--source", action="store_true")
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
