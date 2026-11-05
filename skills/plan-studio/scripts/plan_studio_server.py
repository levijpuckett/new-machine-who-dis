#!/usr/bin/env python3
"""Local plan-studio server: serves a markdown plan as an annotatable HTML page
(or a pre-plan clarifying-questions page), collects the user's comments or
answers, writes them to a JSON file, and exits.

Stdlib only. See ~/.claude/skills/plan-studio/SKILL.md for the workflow.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_PATH = os.path.join(SKILL_DIR, "assets", "template.html")
MARKED_PATH = os.path.join(SKILL_DIR, "assets", "marked.min.js")
PORT_RANGE = 10  # default port, then this many fallbacks


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def js_string_safe(s):
    # Prevent "</script>" inside embedded JSON from terminating the script tag.
    return s.replace("</", "<\\/")


class State:
    def __init__(self, args, mode, plan_md=None, questions=None):
        self.args = args
        self.mode = mode  # "plan" | "questions"
        self.plan_md = plan_md
        self.questions = questions
        self.boot_id = str(uuid.uuid4())
        self.started = time.monotonic()
        self.last_activity = time.monotonic()
        self.client_seen = False
        self.result = None  # {"status": ..., "reason": ..., payload fields}
        self.done = threading.Event()
        self.port = None

    def touch(self):
        self.last_activity = time.monotonic()

    def finish(self, status, reason=None, payload=None):
        if self.done.is_set():
            return
        self.result = {"status": status, "reason": reason, "payload": payload or {}}
        self.done.set()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # silence per-request logging
        pass

    @property
    def state(self):
        return self.server.state

    def _send(self, code, body=None, ctype="application/json"):
        self.send_response(code)
        if body is None:
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_header("Content-Type", f"{ctype}; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
        st = self.state
        if self.path == "/" or self.path.startswith("/?"):
            st.client_seen = True
            st.touch()
            self._send(200, render_page(st), ctype="text/html")
        elif self.path == "/status":
            st.touch()
            self._send(200, json.dumps({
                "app": "plan-studio",
                "mode": st.mode,
                "boot_id": st.boot_id,
                "round": st.args.round,
                "idle_secs": round(time.monotonic() - st.last_activity, 1),
                "client_seen": st.client_seen,
            }))
        elif self.path == "/favicon.ico":
            self._send(204)
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        st = self.state
        if self.path == "/heartbeat":
            st.touch()
            self._send(204)
        elif self.path == "/comments":
            payload = self._read_json()
            self._send(200, json.dumps({"ok": True}))
            st.finish("comments", payload=payload)
        elif self.path == "/answers":
            payload = self._read_json()
            self._send(200, json.dumps({"ok": True}))
            st.finish("answered", payload=payload)
        elif self.path == "/approve":
            payload = self._read_json()
            self._send(200, json.dumps({"ok": True}))
            st.finish("approved", payload=payload)
        elif self.path == "/shutdown":
            self._send(200, json.dumps({"ok": True}))
            st.finish("abandoned", reason="evicted")
        else:
            self._send(404, json.dumps({"error": "not found"}))


def render_page(st):
    with open(TEMPLATE_PATH, encoding="utf-8") as f:
        html = f.read()
    marked_js = ""
    if os.path.exists(MARKED_PATH):
        with open(MARKED_PATH, encoding="utf-8") as f:
            marked_js = f.read()

    if st.mode == "questions":
        n = len(st.questions)
        title = f"{n} question{'s' if n != 1 else ''}"
        plan_json = "null"
        questions_json = js_string_safe(json.dumps(st.questions))
        summary_md = None
    else:
        summary_md = None
        if st.args.summary and os.path.exists(st.args.summary):
            with open(st.args.summary, encoding="utf-8") as f:
                summary_md = f.read()
        title = os.path.basename(st.args.plan)
        for line in st.plan_md.splitlines():
            if line.startswith("# "):
                title = line[2:].strip()
                break
        plan_json = js_string_safe(json.dumps(st.plan_md))
        questions_json = "null"

    return (html
            .replace("__MARKED_JS__", marked_js)
            .replace("__MODE__", st.mode)
            .replace("__PLAN_JSON__", plan_json)
            .replace("__QUESTIONS_JSON__", questions_json)
            .replace("__SUMMARY_JSON__", js_string_safe(json.dumps(summary_md)))
            .replace("__BOOT_ID__", st.boot_id)
            .replace("__ROUND__", str(st.args.round))
            .replace("__PLAN_TITLE__", js_string_safe(json.dumps(title))))


def probe_status(port, timeout=0.5):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/status", timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return None


def post_shutdown(port, timeout=1.0):
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/shutdown", data=b"", method="POST")
        urllib.request.urlopen(req, timeout=timeout)
    except Exception:
        pass


def bind_server(state, preferred_port):
    for i in range(PORT_RANGE):
        port = preferred_port + i
        try:
            server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        except OSError:
            status = probe_status(port)
            # Evict a leftover plan-studio server nobody is looking at; never
            # touch a live one (heartbeats keep idle_secs low while a tab is open).
            if (status and status.get("app") == "plan-studio"
                    and (not status.get("client_seen") or status.get("idle_secs", 0) > 60)):
                post_shutdown(port)
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    time.sleep(0.2)
                    try:
                        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
                        break
                    except OSError:
                        continue
                else:
                    continue
            else:
                continue
        server.state = state
        state.port = port
        return server
    return None


def open_browser(url):
    candidates = []
    for name in ("explorer.exe", "powershell.exe", "wslview", "xdg-open"):
        path = shutil.which(name)
        if path:
            candidates.append((name, path))
    for name, path in candidates:
        if name == "powershell.exe":
            cmd = [path, "-NoProfile", "-Command", f"Start-Process '{url}'"]
        else:
            cmd = [path, url]
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return  # explorer.exe's exit code is meaningless; fire and forget
        except OSError:
            continue


def write_result(state):
    res = state.result
    payload = res["payload"]
    if state.mode == "questions":
        out = {
            "schema": "plan-studio-questions/v1",
            "status": res["status"],
            "reason": res["reason"],
            "questions_file": os.path.abspath(state.args.questions),
            "port": state.port,
            "submitted_at": utc_now(),
            "answers": payload.get("answers") or [],
        }
    else:
        comments = payload.get("comments") or []
        out = {
            "schema": "plan-studio/v1",
            "status": res["status"],
            "reason": res["reason"],
            "plan_file": os.path.abspath(state.args.plan),
            "round": state.args.round,
            "port": state.port,
            "submitted_at": utc_now(),
            "general_comments": payload.get("general_comments") or None,
            "comments": comments,
        }
    tmp = state.args.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    os.replace(tmp, state.args.out)
    return out


def main():
    ap = argparse.ArgumentParser(description="Interactive plan review server")
    ap.add_argument("plan", nargs="?", default=None,
                    help="path to the plan markdown file (review mode)")
    ap.add_argument("--questions", default=None,
                    help="path to a JSON file of clarifying questions (questions mode); "
                         "mutually exclusive with the plan positional argument")
    ap.add_argument("--out", required=True, help="path to write the result JSON")
    ap.add_argument("--port", type=int, default=7357)
    ap.add_argument("--round", type=int, default=1)
    ap.add_argument("--no-open", action="store_true", help="skip launching the browser")
    ap.add_argument("--summary", default=None,
                    help="path to a markdown summary of changes since the last round, "
                         "shown as a banner above the plan")
    ap.add_argument("--open-timeout", type=int, default=300,
                    help="secs to wait for the first page load before giving up")
    ap.add_argument("--idle-timeout", type=int, default=180,
                    help="secs of heartbeat silence before treating the review as abandoned")
    ap.add_argument("--max-session", type=int, default=14400)
    args = ap.parse_args()

    if bool(args.plan) == bool(args.questions):
        print("PLAN_STUDIO_ERROR: pass exactly one of PLAN (positional) or --questions",
              file=sys.stderr)
        return 1
    mode = "questions" if args.questions else "plan"

    plan_md = None
    questions = None
    if mode == "plan":
        try:
            with open(args.plan, encoding="utf-8") as f:
                plan_md = f.read()
        except OSError as e:
            print(f"PLAN_STUDIO_ERROR: cannot read plan file: {e}", file=sys.stderr)
            return 1
    else:
        try:
            with open(args.questions, encoding="utf-8") as f:
                questions = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            print(f"PLAN_STUDIO_ERROR: cannot read/parse questions file: {e}", file=sys.stderr)
            return 1
        if not isinstance(questions, list) or not questions:
            print("PLAN_STUDIO_ERROR: --questions file must be a non-empty JSON array",
                  file=sys.stderr)
            return 1
        for i, q in enumerate(questions):
            if (not isinstance(q, dict) or not q.get("question")
                    or not isinstance(q.get("options"), list) or not q["options"]):
                print(f"PLAN_STUDIO_ERROR: question[{i}] missing required "
                      f"'question'/'options' fields", file=sys.stderr)
                return 1
    if not os.path.exists(TEMPLATE_PATH):
        print(f"PLAN_STUDIO_ERROR: template missing at {TEMPLATE_PATH}", file=sys.stderr)
        return 1
    out_dir = os.path.dirname(os.path.abspath(args.out))
    if not os.path.isdir(out_dir):
        print(f"PLAN_STUDIO_ERROR: output directory does not exist: {out_dir}", file=sys.stderr)
        return 1

    state = State(args, mode, plan_md=plan_md, questions=questions)
    server = bind_server(state, args.port)
    if server is None:
        print(f"PLAN_STUDIO_ERROR: no free port in {args.port}..{args.port + PORT_RANGE - 1}",
              file=sys.stderr)
        return 1

    url = f"http://localhost:{state.port}/"
    if mode == "plan":
        print(f"PLAN_STUDIO: starting round={args.round} port={state.port} "
              f"plan={os.path.abspath(args.plan)} out={os.path.abspath(args.out)}", flush=True)
    else:
        print(f"PLAN_STUDIO: starting mode=questions port={state.port} "
              f"questions={os.path.abspath(args.questions)} out={os.path.abspath(args.out)} "
              f"n={len(questions)}", flush=True)
    print(f"PLAN_STUDIO: url={url}  (open manually if no browser appeared)", flush=True)

    threading.Thread(target=server.serve_forever, daemon=True).start()
    if not args.no_open:
        open_browser(url)

    while not state.done.is_set():
        state.done.wait(timeout=1.0)
        now = time.monotonic()
        if now - state.started > args.max_session:
            state.finish("abandoned", reason="max_session")
        elif not state.client_seen:
            if now - state.started > args.open_timeout:
                state.finish("abandoned", reason="no_client")
        elif now - state.last_activity > args.idle_timeout:
            state.finish("abandoned", reason="heartbeat_lost")

    # Let the final HTTP response flush before tearing the server down.
    time.sleep(0.3)
    server.shutdown()
    out = write_result(state)
    if mode == "plan":
        print(f"PLAN_STUDIO_RESULT: status={out['status']} n={len(out['comments'])} "
              f"general={'yes' if out['general_comments'] else 'no'} "
              f"out={os.path.abspath(args.out)} port={state.port}", flush=True)
    else:
        print(f"PLAN_STUDIO_RESULT: status={out['status']} n={len(out['answers'])} "
              f"out={os.path.abspath(args.out)} port={state.port}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
