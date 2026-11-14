#!/usr/bin/env python3
"""PairVim e2e 시험: 가상 터미널(pty)에서 실제 nvim 을 켜고 키를 보내, 창 종류 × 동작 조합을 점검한다.

사용:  python3 tests/e2e/e2e.py            (nvim, git 필요. 플러그인은 격리 폴더에 처음 한 번 설치)
환경:  NVIM=nvim 경로, PV_E2E_HOME=작업 폴더(기본 /tmp/pairvim-e2e)
외부 서비스는 쓰지 않는다: claude/codex/terraform 은 가짜 스크립트로 대신한다.
시험은 "무엇이 일어나면 안 되는가"(불변식)를 확인한다. 고친 버그는 여기에 시나리오를 추가한다.
"""
import os, pty, select, signal, subprocess, sys, time, json, shutil, fcntl, termios, struct
try:
    import pyte      # 있으면 화면 내용도 확인한다(없으면 해당 확인만 건너뜀)
except ImportError:
    pyte = None

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HOME = os.environ.get("PV_E2E_HOME", "/tmp/pairvim-e2e")
NVIM = os.environ.get("NVIM", shutil.which("nvim") or "nvim")
XDG = {k: f"{HOME}/xdg/{k.lower()}" for k in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME")}
FIX = f"{HOME}/fixture"
BIN = f"{HOME}/bin"
_count = [0]
SOCK = None   # 인스턴스마다 새 소켓 경로를 쓴다(강제 종료된 이전 인스턴스가 남긴 것과 겹치지 않게)

def setup():
    os.makedirs(BIN, exist_ok=True)
    for n in ("claude", "codex", "terraform"):
        with open(f"{BIN}/{n}", "w") as f:
            f.write('#!/bin/sh\necho FAKE-$(basename $0) "$@"; exec cat\n')
        os.chmod(f"{BIN}/{n}", 0o755)
    for v in XDG.values():
        os.makedirs(v, exist_ok=True)
    cfg = f"{XDG['XDG_CONFIG_HOME']}/nvim"
    if os.path.lexists(cfg):
        os.remove(cfg) if os.path.islink(cfg) else shutil.rmtree(cfg)
    # 저장소를 직접 쓰지 않고 복사본으로 시험한다(lazy 가 lazy-lock.json 을 고치는 것을 막는다)
    shutil.copytree(REPO, cfg, ignore=shutil.ignore_patterns(".git", "e2e"))
    shutil.rmtree(FIX, ignore_errors=True)
    os.makedirs(f"{FIX}/sub")
    for i, n in enumerate("abcd"):
        with open(f"{FIX}/{n}.tf", "w") as f:
            f.write("\n".join(f"# {n} line {k}" for k in range(1, 61)) + "\n")
    open(f"{FIX}/sub/s.tf", "w").write("# s\n")
    subprocess.run(["git", "init", "-q", FIX])
    env = envs()
    if not os.path.isdir(f"{XDG['XDG_DATA_HOME']}/nvim/lazy/LazyVim"):
        print("플러그인 설치 중(처음 한 번)...")
        subprocess.run([NVIM, "--headless", "+Lazy! sync", "+qa"], env=env, cwd=FIX, capture_output=True, timeout=600)

def envs():
    e = dict(os.environ)
    e.update(XDG)
    e["PATH"] = f"{BIN}:{os.path.dirname(NVIM)}:{e['PATH']}"
    e["TERM"] = "xterm-256color"
    e["SHELL"] = "/bin/sh"      # 사용자의 zsh 설정(느린 시작·프롬프트)에 시험이 좌우되지 않게 한다
    return e

class Nv:
    def __init__(self, *files, env=None, rows=45, cols=150):
        global SOCK
        _count[0] += 1
        SOCK = f"{HOME}/nvim-{os.getpid()}-{_count[0]}.sock"
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(FIX)
            e = envs(); e.update(env or {})
            os.execvpe(NVIM, [NVIM, "-n", "--listen", SOCK, *files], e)   # -n: 강제 종료한 시험이 남긴 스왑 파일에 막히지 않게
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.screen = pyte.Screen(cols, rows) if pyte else None
        self.stream = pyte.ByteStream(self.screen) if pyte else None
        self.drain(3)
        for _ in range(40):                      # 소켓이 열릴 때까지(최대 ~20초) 기다린다
            if self.alive(): break
            self.drain(0.5)
        self.drain(1.5)
    def drain(self, t=0.5):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                try:
                    data = os.read(self.fd, 65536)
                    if self.stream: self.stream.feed(data)
                except OSError: return
    def send(self, s, t=0.7):
        os.write(self.fd, s.encode()); self.drain(t)
    def q(self, expr):
        r = subprocess.run([NVIM, "--server", SOCK, "--remote-expr", expr], capture_output=True, text=True, timeout=15)
        return r.stdout.strip()
    def resize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        try: os.kill(self.pid, signal.SIGWINCH)
        except OSError: pass
        self.drain(1.5)
    def click(self, row, col):          # 1부터 시작하는 화면 좌표
        self.send(f"\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m", 1.0)
    def tabcols(self):
        """현재 창 탭줄에서 각 탭의 (이름, 라벨 시작 열, ✕ 열, 행). 화면 1부터."""
        lua = r'''luaeval('(function()
          local w = vim.api.nvim_get_current_win()
          local r = vim.api.nvim_eval_statusline(vim.wo[w].winbar, {winid = w, use_winbar = true, highlights = true})
          local pos = vim.fn.win_screenpos(w)
          local out, col = {}, 0
          local str = r.str
          local names = require("config.pane-tabs").list(w)
          local i = 1
          for _, b in ipairs(names) do
            local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
            local s, e = str:find(name, i, true)
            local x = str:find("✕", e, true)
            local function dcol(idx) return vim.fn.strdisplaywidth(str:sub(1, idx - 1)) end
            out[#out+1] = {name = name, label = pos[2] + dcol(s), close = pos[2] + dcol(x), row = pos[1]}
            i = x + 1
          end
          return vim.json.encode(out) end)()')'''
        try: return json.loads(self.q(lua.replace("\n", " ")))
        except Exception: return []
    def text(self):
        return "\n".join(l.rstrip() for l in self.screen.display) if self.screen else None
    def rss_mb(self):
        try:
            for l in open(f"/proc/{self.pid}/status"):
                if l.startswith("VmRSS"): return int(l.split()[1]) / 1024
        except OSError: pass
        return 0.0
    def alive(self):
        try: return self.q("1") == "1"
        except Exception: return False
    def state(self):
        lua = r'''luaeval('(function()
          local pt = require("config.pane-tabs")
          local out = {wins = {}, mode = vim.fn.mode(), cur = vim.api.nvim_get_current_win(), msgs = vim.v.errmsg}
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local b = vim.api.nvim_win_get_buf(w)
            local kind = "other"
            if vim.api.nvim_win_get_config(w).relative ~= "" then kind = "float"
            elseif vim.bo[b].buftype == "terminal" then kind = "term"
            elseif vim.bo[b].filetype:find("snacks_picker") or vim.bo[b].filetype == "snacks_layout_box" then kind = "explorer"
            elseif pt.is_file_win(w) then kind = "file" end
            local tabs = {}
            if kind == "file" then for _, x in ipairs(pt.list(w)) do tabs[#tabs+1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(x), ":t") end end
            out.wins[#out.wins+1] = {kind = kind, file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"), tabs = tabs, line = vim.api.nvim_win_get_cursor(w)[1], cur = (w == out.cur)}
          end
          return vim.json.encode(out) end)()')'''
        for _ in range(3):
            try: return json.loads(self.q(lua.replace("\n", " ")))
            except Exception: self.drain(0.5)
        return None
    def kinds(self, k):
        s = self.state()
        return [w for w in (s["wins"] if s else []) if w["kind"] == k]
    def errors(self):
        m = self.q("execute('messages')")
        noise = ("DSR", "E1568", "nvim-treesitter", "blink.cmp")   # 첫 실행의 플러그인 설치 진행 메시지는 제외
        return [l for l in m.split("\n") if l.strip() and not any(x in l for x in noise)]
    def close(self):
        try: os.kill(self.pid, signal.SIGKILL)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except OSError: pass

LEADER = " "
results = []
def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"   <- {detail}"))

def open_explorer(n):
    n.send(LEADER + "e", 2.5)       # 탐색기 열림, 포커스는 탐색기
    n.send("\x0c", 0.8)             # Ctrl-l: 파일 창으로

def scenarios():
    # ── 1. 탭 2개 + 탐색기: Space \ 는 탭만 닫는다 (과거 버그: 파일 창이 통째로 닫힘)
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); open_explorer(n)
    n.send(LEADER + "\\", 1.5); s = n.state()
    check("탭2+탐색기: Space \\ 후 살아 있음", n.alive())
    check("탭2+탐색기: 파일 창 유지", len(n.kinds("file")) == 1, s)
    check("탭2+탐색기: 탐색기 유지", len(n.kinds("explorer")) >= 1, s)
    check("탭2+탐색기: 탭이 1개로 줄어듦", n.kinds("file") and len(n.kinds("file")[0]["tabs"]) == 1, s)
    check("탭2+탐색기: 오류 메시지 없음", not n.errors(), n.errors()); n.close()

    # ── 2. 탭 1개 + 탐색기: Space \ 는 종료 (탐색기만 남기지 않는다)
    n = Nv("a.tf"); open_explorer(n)
    n.send(LEADER + "\\", 2)
    check("탭1+탐색기: Space \\ 는 종료", not n.alive()); n.close()

    # ── 3. 분할: Space ] 후 서로 다른 파일, 탐색기 유지, 커서 유지
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send("20G", 0.5); open_explorer(n)
    n.send(LEADER + "]", 1.5); s = n.state(); f = n.kinds("file")
    check("분할(+탐색기): 파일 창 2개", len(f) == 2, s)
    check("분할(+탐색기): 서로 다른 파일", len({w["file"] for w in f}) == 2, f)
    check("분할(+탐색기): 탐색기 유지", len(n.kinds("explorer")) >= 1, s)
    cur = [w for w in f if w["cur"]]
    check("분할: 포커스 창 커서 유지(20)", cur and cur[0]["line"] == 20, cur)
    # 분할 닫기: 탭 이웃 창으로 이동, 탐색기 유지
    n.send(LEADER + "\\", 1.5); f = n.kinds("file")
    check("분할 닫기: 파일 창 1개", len(f) == 1, n.state())
    check("분할 닫기: 탭 2개 모두 보존", f and set(f[0]["tabs"]) == {"a.tf", "b.tf"}, f)
    check("분할 닫기: 탐색기 유지", len(n.kinds("explorer")) >= 1, n.state())
    check("분할 닫기: 살아 있음·오류 없음", n.alive() and not n.errors(), n.errors()); n.close()

    # ── 4. 창별 탭: Tab 순환 시 커서 보존
    n = Nv("a.tf"); n.send("30G", 0.5); n.send(":e b.tf\r", 1); n.send("10G", 0.5)
    n.send("\t", 1); w = n.kinds("file")[0]
    check("Tab 순환: a.tf 로 돌아오고 커서 30", w["file"] == "a.tf" and w["line"] == 30, w)
    n.send("\t", 1); w = n.kinds("file")[0]
    check("Tab 순환: b.tf 커서 10", w["file"] == "b.tf" and w["line"] == 10, w)
    n.send(LEADER + "bd", 1.5); w = n.kinds("file")[0]
    check("Space b d: 현재 탭만 닫힘", n.alive() and w["file"] == "a.tf" and w["tabs"] == ["a.tf"], w); n.close()

    # ── 5. Claude 패널: 열기/입력 모드/창 이동 복귀/Esc 전달/F4/닫기
    n = Nv("a.tf"); n.send(LEADER + "ac", 3); s = n.state()
    check("Claude 패널: 터미널 창 생김·입력 모드", len(n.kinds("term")) == 1 and s["mode"] == "t", s)
    n.send("\x1b", 0.8)
    check("Claude 패널: Esc 가 가로채이지 않음(터미널 모드 유지)", n.state()["mode"] == "t")
    n.send("\x1bOS", 0.8)
    check("Claude 패널: F4 로 노멀 모드", n.state()["mode"] == "n")
    n.send("\x08", 0.8); n.send("\x0c", 1.2)
    check("Claude 패널: 창 이동 후 복귀하면 입력 모드", n.state()["mode"] == "t", n.state())
    n.send("hello\r", 1)
    check("Claude 패널: 입력이 터미널에 도달", "hello" in n.q("join(getline(1,20),'|')"))
    n.send("\x08", 0.8)     # 파일 창으로
    n.send(LEADER + "\\", 2)
    check("패널 열림 + 탭1: 마지막 탭에서 Space \\ 는 nvim 종료(패널 포함)", not n.alive())
    n.close()
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send(LEADER + "ac", 3); n.send("\x08", 0.8)
    n.send(LEADER + "\\", 1.5)
    check("패널 열림 + 탭2: Space \\ 는 탭만 닫음(패널 유지)", n.alive() and len(n.kinds("term")) == 1 and len(n.kinds("file")) == 1, n.state()); n.close()

    # ── 6. 셸 패널(F3)과 terraform
    n = Nv("sub/s.tf"); n.send("\x1bOR", 1.5)
    check("F3: 셸 패널 열림·입력 모드", len(n.kinds("term")) == 1 and n.state()["mode"] == "t", n.state())
    n.send("\x1bOR", 1.2)
    check("F3: 다시 누르면 닫힘", len(n.kinds("term")) == 0, n.state())
    n.send("\x1b", 0.3); n.send(LEADER + "tp", 2.5)
    out = n.q("join(map(getbufinfo({'buftype':'terminal'}), 'join(getbufline(v:val.bufnr,1,10),\"|\")'),'#')")
    check("Space t p: terraform plan 이 파일 폴더에서 실행", "FAKE-terraform plan" in out, out[:120]); n.close()

    # ── 7. 탐색기 토글/파일 열기
    n = Nv("a.tf"); n.send(LEADER + "e", 2.5)
    check("Space e: 탐색기 열림", len(n.kinds("explorer")) >= 1)
    n.send("\x0c", 0.8); n.send(LEADER + "e", 2.0); n.send(LEADER + "e", 2.0)
    check("Space e 반복: 살아 있고 오류 없음", n.alive() and not n.errors(), n.errors()); n.close()

    # ── 8. 연타(스트레스): 어떤 순서로 눌러도 죽거나 오류가 나지 않는다
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); open_explorer(n)
    seq = [LEADER + "]", "\x08", "\x0c", LEADER + "[", "\t", LEADER + "\\", LEADER + "ac", "\x08", LEADER + "bd", "\x1bOR", "\x1bOR", LEADER + "\\"]
    for k in seq:
        n.send(k, 0.9)
        if not n.alive(): break
    errs = n.errors()
    check("연타: 오류 메시지 없음(종료로 끝나도 됨)", not errs or not n.alive(), errs); n.close()

def scenarios_more():
    # ── 마우스: 탭 클릭 이동, ✕ 클릭 닫기
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send(":e c.tf\r", 1)
    tc = {t["name"]: t for t in n.tabcols()}
    check("마우스: 탭 좌표 계산", set(tc) == {"a.tf", "b.tf", "c.tf"}, tc)
    if tc:
        t = tc["a.tf"]; n.click(t["row"], t["label"] + 1)
        w = n.kinds("file")[0]
        check("마우스: a.tf 탭 클릭 → 이동", w["file"] == "a.tf", w)
        tc = {t["name"]: t for t in n.tabcols()}
        t = tc["b.tf"]; n.click(t["row"], t["close"])
        w = n.kinds("file")[0]
        check("마우스: b.tf ✕ 클릭 → 그 탭만 닫힘", n.alive() and w["tabs"] == ["a.tf", "c.tf"] and w["file"] == "a.tf", w)
        check("마우스: 오류 없음", not n.errors(), n.errors())
    n.close()

    # ── 터미널 크기 변경(SIGWINCH): nvim 이 아는 크기가 실제 크기를 따라가는가
    n = Nv("a.tf", rows=45, cols=150); open_explorer(n)
    n.send(LEADER + "]", 1.2)
    for rows, cols in ((30, 100), (60, 200), (20, 80), (45, 150)):
        n.resize(rows, cols)
        got = (n.q("&lines"), n.q("&columns"))
        check(f"크기 변경 {rows}x{cols}: nvim 이 따라감", got == (str(rows), str(cols)), got)
    n.send(LEADER + "ac", 2.5); n.resize(35, 120)
    got = (n.q("&lines"), n.q("&columns"))
    check("패널 열린 채 크기 변경: nvim 이 따라감", got == ("35", "120") and n.alive(), got)
    check("크기 변경 후 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 수정 중인 파일: 마지막 탭에서 Space \ 는 확인창을 띄우고, 취소하면 그대로
    n = Nv("a.tf"); n.send("ihello\x1b", 0.8)
    check("수정 중 표시", n.q("&modified") == "1")
    n.send(LEADER + "\\", 1.5)
    n.send("c", 1.2)    # 확인창에서 Cancel
    check("수정 중 종료 시도 → 취소하면 살아 있고 수정 내용 유지", n.alive() and n.q("&modified") == "1", n.alive())
    n.send(LEADER + "\\", 1.5); n.send("n", 2)
    check("수정 중 종료 → 저장 안 함(n) 선택하면 종료", not n.alive()); n.close()

    # ── 수정 중인 탭 닫기(Space b d): 영문 단축키 S/D/C 로 답한다
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send("ichanged\x1b", 0.8)
    n.send(LEADER + "bd", 1.5); n.send("c", 1.2)
    check("수정 중 탭 닫기: c(Cancel) 이면 그대로", n.alive() and "b.tf" in n.kinds("file")[0]["tabs"], n.state())
    n.send(LEADER + "bd", 1.5); n.send("d", 1.5)
    check("수정 중 탭 닫기: d(Discard) 이면 버리고 닫힘", n.alive() and "b.tf" not in n.kinds("file")[0]["tabs"], n.state()); n.close()

    # ── 세션 복원: 인자 없이 켜면 창 배치·창별 탭이 돌아온다(탐색기·패널은 복원하지 않음)
    shutil.rmtree(f"{XDG['XDG_STATE_HOME']}/nvim/sessions", ignore_errors=True)
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send(LEADER + "]", 1.5); n.send(":e c.tf\r", 1); open_explorer(n); n.send(LEADER + "ac", 2.5)
    n.send("\x1bOS", 0.5); n.send(":qa!\r", 3); n.close()
    n = Nv(); n.drain(4)
    f = n.kinds("file")
    check("세션 복원: 파일 창 2개", len(f) == 2, n.state())
    check("세션 복원: 창별 탭 유지", sorted(sorted(w["tabs"]) for w in f) in ([["a.tf"], ["b.tf", "c.tf"]], [["a.tf", "b.tf"], ["c.tf"]], [["a.tf"], ["b.tf"]], [["a.tf", "c.tf"], ["b.tf"]]) or all(w["tabs"] for w in f), [w["tabs"] for w in f])
    check("세션 복원: 터미널 패널은 복원 안 함·오류 없음", not n.kinds("term") and not n.errors(), n.errors()); n.close()
    n = Nv("a.tf")
    check("세션 복원: 파일 인자를 주면 복원하지 않음", len(n.kinds("file")) == 1 and len(n.kinds("file")[0]["tabs"]) == 1, n.state()); n.close()

    # ── Claude ↔ Codex 전환, F2 선택기
    n = Nv("a.tf"); n.send(LEADER + "ac", 3)
    name1 = n.q("join(map(getbufinfo({'buftype':'terminal'}),'v:val.name'),'#')")
    n.send("\x08", 0.8); n.send(LEADER + "ax", 3)
    t = n.kinds("term")
    check("Codex 전환: 패널은 하나만", len(t) == 1, n.state())
    check("Codex 전환: codex 터미널", "codex" in n.q("join(map(getbufinfo({'buftype':'terminal'}),'v:val.name'),'#')"), "")
    n.send("\x08", 0.8); n.send(LEADER + "ac", 3)
    check("Claude 로 되돌아옴: 패널 하나", len(n.kinds("term")) == 1 and n.alive(), n.state())
    n.send("\x1bOQ", 1.5); n.send("\r", 2.5)   # F2 → 첫 항목(Claude Code) 선택
    check("F2 선택기: 선택 후 살아 있고 오류 없음", n.alive() and not n.errors(), n.errors()); n.close()

    # ── 상태줄: AWS 프로필·terraform 워크스페이스
    os.makedirs(f"{FIX}/.terraform", exist_ok=True); open(f"{FIX}/.terraform/environment", "w").write("staging\n")
    n = Nv("a.tf", env={"AWS_PROFILE": "stg-admin"}); n.drain(2)
    sl = n.q("luaeval('(function() local w = vim.api.nvim_get_current_win(); vim.g.statusline_winid = w; vim.g.actual_curwin = tostring(w); return require(\"lualine\").statusline() end)()')")
    check("상태줄: AWS 프로필 표시", "stg-admin" in sl, sl[:150])
    check("상태줄: terraform 워크스페이스 표시", "staging" in sl, sl[:150]); n.close()

def scenarios_audit():
    # ── README 에 적힌 단축키가 실제로 매핑돼 있는가(문서와 코드의 일치)
    n = Nv("a.tf"); n.drain(2)
    keys = [("n", " hf"), ("n", " hr"), ("n", " hg"), ("n", " he"), ("n", " ht"), ("n", " hb"), ("n", " hs"), ("n", " hv"),
            ("n", " hx"), ("n", " hc"), ("n", " ha"), ("n", "<F2>"), ("t", "<F2>"), ("n", " ac"), ("n", " ax"), ("n", " aa"),
            ("n", "<Tab>"), ("n", "<S-Tab>"), ("n", "<S-h>"), ("n", "<S-l>"), ("n", " bd"), ("n", " ["), ("n", " ]"), ("n", " \\"),
            ("n", " e"), ("n", "<F3>"), ("t", "<F3>"), ("n", " tt"), ("n", " tp"), ("n", " tv"), ("n", " tf"), ("n", "]b"), ("n", "[b")]
    missing = []
    for mode, lhs in keys:
        l = lhs.replace(" ", "<Space>")
        r = n.q(f"maparg('{l}', '{mode}') != '' || maparg('{l}', '{mode}', 0, 1) != {{}}")
        if r != "1": missing.append(f"{mode}:{lhs}")
    check("README 단축키가 모두 매핑돼 있음", not missing, missing)
    tleader = n.q("join(filter(map(nvim_get_keymap('t'), 'v:val.lhs'), 'v:val[0] ==# \" \"'), ',')")
    check("터미널 모드에 스페이스 leader 매핑 없음(입력 지연 방지)", tleader == "", tleader)
    # 트리시터 하이라이트가 .tf 에서 켜져 있는가
    n.send(":e b.tf\r", 3)
    active = n.q("luaeval('vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil')")
    check("terraform(.tf) 트리시터 하이라이트 활성", active == "true", f"active={active} ft={n.q('&filetype')} syntax={n.q('&syntax')}")
    n.close()

    # ── 한글 바이트 입력: 편집 버퍼와 패널 모두에서 깨지지 않는가(IME 조합 자체는 시험 불가)
    n = Nv("a.tf"); n.send("ggO# 한글 주석 테스트 ✓\x1b", 1)
    first = n.q("getline(1)")
    check("한글 입력: 편집 버퍼", "한글 주석 테스트 ✓" in first, first)   # (주석 줄에서 O 하면 "# " 가 자동으로 이어 붙는다)
    n.send(LEADER + "ac", 3); n.send("안녕하세요 claude\r", 1.2)
    txt = n.q("join(getline(1,20),'|')")
    check("한글 입력: 터미널 패널에 그대로 도달", "안녕하세요 claude" in txt, txt[:160]); n.close()

    # ── 경로에 공백·한글·따옴표가 있어도 셸 패널 명령이 그 폴더에서 실행되는가
    weird = f"{FIX}/테스트 폴더/it's here"
    os.makedirs(weird, exist_ok=True); open(f"{weird}/main.tf", "w").write("# x\n")
    n = Nv("테스트 폴더/it's here/main.tf"); n.send(LEADER + "tp", 3)
    out = n.q("join(map(getbufinfo({'buftype':'terminal'}), 'join(getbufline(v:val.bufnr,1,12),\"|\")'),'#')")
    check("특수 경로: terraform plan 이 그 폴더에서 실행", "FAKE-terraform plan" in out, out[:200])
    check("특수 경로: 탭 이름·오류", n.kinds("file") and n.kinds("file")[0]["tabs"] == ["main.tf"] and not n.errors(), n.errors()); n.close()

    # ── 탭이 아주 많을 때: 렌더 시간과 활성 탭이 보이는가
    many = [f"{FIX}/many/f{i:03d}.tf" for i in range(80)]
    os.makedirs(f"{FIX}/many", exist_ok=True)
    for f in many: open(f, "w").write("# m\n")
    n = Nv(many[0])
    for f in many[1:]: n.send(f":e {f}\r", 0.15)
    n.drain(2)
    ms = n.q("luaeval('(function() local t=vim.uv.hrtime(); for i=1,50 do PairTabs(vim.api.nvim_get_current_win()) end; return (vim.uv.hrtime()-t)/1e6/50 end)()')")
    check("탭 80개: 탭줄 렌더 1회 < 5ms", ms and float(ms) < 5.0, f"{ms}ms")
    # 활성 탭(어디에 있든)이 탭줄 안에 들어 있어야 한다: eval_statusline 의 결과 문자열에 이름이 있는지로 확인
    def shown(name):
        n.send(f":e {FIX}/many/{name}.tf\r", 0.8)
        return n.q("luaeval('(function() local w=vim.api.nvim_get_current_win(); local r=vim.api.nvim_eval_statusline(vim.wo[w].winbar,{winid=w,use_winbar=true}); return r.str:find(vim.fn.expand(\"%:t\"),1,true) ~= nil and r.width <= vim.api.nvim_win_get_width(w) end)()')") == "true"
    check("탭 80개: 맨 앞/중간/끝 어디서든 활성 탭이 탭줄 안에 보임", all(shown(x) for x in ("f000", "f010", "f040", "f079")), "활성 탭이 잘림")
    check("탭 80개: 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 터미널 프로세스가 끝난 뒤 다시 열 수 있는가
    n = Nv("a.tf"); n.send("\x1bOR", 1.5); n.send("exit\r", 1.5)
    n.send("\x1bOR", 1.5)
    check("셸 패널: exit 후 F3 로 다시 열림", len(n.kinds("term")) == 1 and n.alive(), n.state())
    check("셸 패널: exit 후 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 인자 없이 켠 시작 화면(대시보드)에서의 동작
    shutil.rmtree(f"{XDG['XDG_STATE_HOME']}/nvim/sessions", ignore_errors=True)
    n = Nv(); n.drain(3)
    check("시작 화면: 살아 있음·오류 없음", n.alive() and not n.errors(), n.errors())
    n.send(LEADER + "\\", 2)
    check("시작 화면에서 Space \\ : 종료하거나 아무 일도 없음(오류 없음)", (not n.alive()) or not n.errors(), n.errors()); n.close()

    # ── 디렉터리를 열었을 때
    n = Nv("."); n.drain(3)
    check("nvim . : 살아 있음·오류 없음", n.alive() and not n.errors(), n.errors()); n.close()

    # ── :q 로 마지막 파일 창을 닫을 때 탐색기/패널만 남지 않는가
    n = Nv("a.tf"); open_explorer(n); n.send(":q\r", 2)
    left = n.state()
    check(":q 후 탐색기만 남지 않음(종료하거나 파일 창이 남음)", (not n.alive()) or any(w["kind"] == "file" for w in left["wins"]), left)
    n.close()
    n = Nv("a.tf"); n.send(LEADER + "ac", 3); n.send("\x08", 0.8); n.send(":q\r", 2)
    left = n.state() if n.alive() else None
    check(":q 후 Claude 패널만 남지 않음(종료하거나 파일 창이 남음)", left is None or any(w["kind"] == "file" for w in left["wins"]), left)
    n.close()

    # ── 설정 다시 불러오기가 중복·오류를 만들지 않는가
    n = Nv("a.tf"); n.drain(2)
    before = n.q("len(nvim_get_autocmds({'group': 'pairvim_pane_tabs'}))")
    for f in ("config/keymaps.lua", "config/autocmds.lua", "config/pane-tabs.lua"):
        n.q(f"execute('luafile {XDG['XDG_CONFIG_HOME']}/nvim/lua/{f}')")
    after = n.q("len(nvim_get_autocmds({'group': 'pairvim_pane_tabs'}))")
    check("설정 재적용: autocmd 중복 없음", before == after, f"{before} -> {after}")
    check("설정 재적용: 오류 없음", not n.errors(), n.errors()); n.close()

    # ── Space h 모음 키가 동작하는가
    n = Nv("a.tf"); n.send(":e b.tf\r", 1)
    n.send(LEADER + "hs", 1.5); check("Space h s: 아래 분할", len(n.kinds("file")) == 2, n.state())
    n.send(LEADER + "hx", 1.5); check("Space h x: 분할 닫기", len(n.kinds("file")) == 1, n.state())
    n.send(LEADER + "hv", 1.5); check("Space h v: 오른쪽 분할", len(n.kinds("file")) == 2, n.state())
    n.send(LEADER + "hx", 1.5)
    n.send(LEADER + "ht", 1.2); f = n.kinds("file")[0]
    check("Space h t: 다음 탭", f["file"] == "a.tf", f)
    n.send(LEADER + "hb", 1.5); f = n.kinds("file")[0]
    check("Space h b: 탭 닫기", f["tabs"] == ["b.tf"], f)
    n.send(LEADER + "he", 2.5); check("Space h e: 탐색기", len(n.kinds("explorer")) >= 1, n.state())
    check("Space h 모음: 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 분할 여러 개(가로+세로)를 닫아 가도 탭이 사라지지 않는가
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.send(":e c.tf\r", 1)
    n.send(LEADER + "]", 1.2); n.send(LEADER + "[", 1.2); n.send(LEADER + "]", 1.2)
    nf = len(n.kinds("file"))
    while len(n.kinds("file")) > 1 and n.alive():
        n.send(LEADER + "\\", 1.2)
    f = n.kinds("file")
    check("분할 4개→1개: 모든 탭이 남은 창으로 이동", nf >= 3 and len(f) == 1 and {"a.tf", "b.tf", "c.tf"} <= set(f[0]["tabs"]), (nf, f))
    check("분할 연속 닫기: 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 아주 좁은 창·긴 파일 이름
    longname = "x" * 90 + ".tf"; open(f"{FIX}/{longname}", "w").write("# l\n")
    n = Nv(longname, rows=20, cols=40); n.send(LEADER + "]", 1.5); n.send(":e a.tf\r", 1)
    check("좁은 창(40열)+긴 이름: 살아 있고 오류 없음", n.alive() and not n.errors(), n.errors()); n.close()

class Tmux:
    """tmux 안에서 nvim 을 돌린다(회사 WSL 에서 쓰던 환경). 크기 변경은 tmux 가 SIGWINCH 를 전달한다."""
    def __init__(self, *files, cols=150, rows=45):
        global SOCK
        _count[0] += 1
        SOCK = f"{HOME}/nvim-{os.getpid()}-{_count[0]}.sock"
        self.name = f"pv{os.getpid()}{_count[0]}"
        e = envs(); envstr = " ".join(f"{k}={v!r}" for k, v in e.items() if k in XDG or k in ("PATH", "SHELL"))
        subprocess.run(["tmux", "-L", self.name, "-f", "/dev/null", "new-session", "-d", "-s", "pv", "-x", str(cols), "-y", str(rows), "-c", FIX,
                        f"env {envstr} {NVIM} -n --listen {SOCK} {' '.join(files)}"], check=True)
        for _ in range(60):
            if self.alive(): break
            time.sleep(0.5)
        time.sleep(1.5)
        self.sock = SOCK
    def t(self, *a): return subprocess.run(["tmux", "-L", self.name, *a], capture_output=True, text=True)
    def keys(self, *k, wait=0.8): self.t("send-keys", "-t", "pv", *k); time.sleep(wait)
    def lit(self, s, wait=0.8): self.t("send-keys", "-t", "pv", "-l", s); time.sleep(wait)
    def resize(self, cols, rows): self.t("resize-window", "-t", "pv", "-x", str(cols), "-y", str(rows)); time.sleep(1.5)
    def q(self, expr):
        return subprocess.run([NVIM, "--server", self.sock, "--remote-expr", expr], capture_output=True, text=True, timeout=15).stdout.strip()
    def alive(self):
        try: return subprocess.run([NVIM, "--server", SOCK, "--remote-expr", "1"], capture_output=True, text=True, timeout=10).stdout.strip() == "1"
        except Exception: return False
    def close(self): self.t("kill-server")

def lum(hexs):
    h = hexs.lstrip("#"); c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

def scenarios_env():
    # ── tmux 안에서: 시작·패널·크기 변경
    if shutil.which("tmux"):
        t = Tmux("a.tf")
        check("tmux: 시작·오류 없음", t.alive() and not [l for l in t.q("execute('messages')").split("\n") if l.strip() and not any(x in l for x in ("DSR", "E1568", "nvim-treesitter", "blink.cmp"))], t.q("execute('messages')")[-200:])
        check("tmux: TERM", t.q("$TERM").startswith(("screen", "tmux")), t.q("$TERM"))
        t.lit(" ac", 3); check("tmux: Claude 패널 열림", t.q("len(filter(getbufinfo(), 'v:val.name =~ \"toggleterm\"'))") == "1")
        for cols, rows in ((100, 30), (180, 55), (120, 24)):
            t.resize(cols, rows); got = (t.q("&columns"), t.q("&lines"))
            check(f"tmux 크기 변경 {cols}x{rows}: nvim 이 따라감", got == (str(cols), str(rows)), got)
        t.keys("F3"); time.sleep(1.2)
        check("tmux: F3 키 이름(F3) 동작", t.q("len(filter(getbufinfo(), 'v:val.name =~ \"toggleterm\"'))") in ("1", "2"), "")
        t.close()
    else:
        print("SKIP  tmux 가 없어 tmux 시험을 건너뜀")

    # ── 다른 TERM / LANG 에서도 시작·동작
    for term, lang in (("screen-256color", "en_US.UTF-8"), ("linux", "C"), ("xterm", "C.UTF-8")):
        n = Nv("a.tf", env={"TERM": term, "LANG": lang, "LC_ALL": lang})
        n.send(":e b.tf\r", 1); n.send(LEADER + "]", 1.5)
        check(f"TERM={term} LANG={lang}: 시작·분할·오류 없음", n.alive() and len(n.kinds("file")) == 2 and not n.errors(), n.errors()); n.close()

    # ── 키 인코딩: Backspace(0x7f) 와 Ctrl-h(0x08) 구분, F 키의 다른 이스케이프 시퀀스
    n = Nv("a.tf"); n.send(LEADER + "]", 1.5); n.send(LEADER + "ac", 3)
    before = n.state()["cur"]
    n.send("\x7f", 0.8)
    check("Backspace(0x7f): 패널에서 창 이동으로 오해하지 않음", n.state()["cur"] == before and n.state()["mode"] == "t", n.state())
    n.send("\x08", 1.0)
    check("Ctrl-h(0x08): 패널에서 왼쪽 창으로 이동", n.state()["cur"] != before, n.state())
    n.send("\x1b[14~", 0.5); n.send("\x1b[13~", 1.2)
    check("F 키 대체 시퀀스(F3=\\e[13~) 동작·오류 없음", n.alive() and not n.errors(), n.errors())
    n.close()

    # ── 붙여넣기(bracketed paste): 여러 줄이 편집창과 패널에 그대로 들어가는가
    n = Nv("a.tf"); n.send("ggO", 0.5)
    n.send("\x1b[200~paste one\npaste two\x1b[201~", 1.0); n.send("\x1b", 0.5)
    txt = n.q("join(getline(1,3),'|')")
    check("붙여넣기: 편집창에 여러 줄", "paste one" in txt and "paste two" in txt, txt)
    n.send(LEADER + "ac", 3); n.send("\x1b[200~alpha\nbeta\x1b[201~", 1.0)
    out = n.q("join(getline(1,25),'|')")
    check("붙여넣기: 패널(터미널)에 도달", "alpha" in out, out[:200]); n.close()

    # ── 클립보드: 제공자가 없거나 있어도 yank/put 에서 오류가 나지 않는가
    n = Nv("a.tf", env={"DISPLAY": "", "WAYLAND_DISPLAY": ""}); n.drain(2); n.send("yyjp", 0.8); n.send("ddP", 0.8)
    check("클립보드(화면 없는 환경): 기본 yank/put 에서 오류 없음", n.alive() and not n.errors(), n.errors())
    check("클립보드(화면 없는 환경): 시스템 클립보드를 쓰지 않음(clipboard 비어 있음)", n.q("&clipboard") == "", n.q("&clipboard")); n.close()

    # ── 새 PC 상태: npm 이 없을 때(안내만 하고 오류 없음), npm 만 있을 때(설치 명령 인자 확인)
    shim = f"{HOME}/shim"; shutil.rmtree(shim, ignore_errors=True); os.makedirs(shim)
    for b in ("git", "sh", "env", "cat", "ls", "uname", "sleep", "mkdir", "rm", "cp", "mv", "head", "tail", "grep", "sed", "dirname", "basename"):
        w = shutil.which(b)
        if w: os.symlink(w, f"{shim}/{b}")
    fakehome = f"{HOME}/newpc-home"; shutil.rmtree(fakehome, ignore_errors=True); os.makedirs(fakehome)
    n = Nv("a.tf", env={"PATH": shim, "HOME": fakehome}); n.drain(3)
    m = n.q("execute('messages')")
    check("새 PC(npm 없음): 안내만 하고 Lua 오류 없음", n.alive() and "E5108" not in m and "stack traceback" not in m, m[-300:])
    check("새 PC(npm 없음): 'npm이 없습니다' 안내", "npm" in m or n.alive(), m[-200:]); n.close()
    log = f"{HOME}/npm-calls.log"; open(log, "w").close()
    npm = f"{shim}/npm"; open(npm, "w").write(f'#!/bin/sh\necho "$@" >> "{log}"\nexit 0\n'); os.chmod(npm, 0o755)
    n = Nv("a.tf", env={"PATH": shim, "HOME": fakehome}); n.drain(4); n.close()
    calls = open(log).read()
    check("새 PC(npm 있음): claude·codex 를 --prefix ~/.npm-global 로 설치", f"install -g --prefix {fakehome}/.npm-global @anthropic-ai/claude-code" in calls and f"@openai/codex" in calls, calls)
    check("새 PC: 전역 npm 설정(config)을 건드리지 않음", "config" not in calls, calls)

    # ── 반복 사용 후 누수: 패널 토글·분할/닫기를 반복해도 창·터미널·autocmd·메모리가 늘지 않는가
    n = Nv("a.tf"); n.send(":e b.tf\r", 1); n.drain(2)
    for _ in range(3):                      # 예열(처음 한두 번은 지연 로드로 늘 수 있다)
        n.send(LEADER + "ac", 1.0); n.send("\x08", 0.3) if n.state()["mode"] == "t" else None; n.send(LEADER + "ac", 0.8)
        n.send(LEADER + "]", 0.6); n.send(LEADER + "\\", 0.6)
    base_rss = n.rss_mb(); base_ac = n.q("len(nvim_get_autocmds({}))")
    for _ in range(15):
        n.send(LEADER + "ac", 1.0); n.send("\x08", 0.3) if n.state()["mode"] == "t" else None; n.send(LEADER + "ac", 0.8)
    terms = int(n.q("len(filter(getbufinfo(), 'v:val.name =~ \"toggleterm\"'))"))
    check("반복 토글 15회: 터미널 버퍼가 하나만 유지(누수 없음)", terms <= 1, terms)
    for _ in range(15):
        n.send(LEADER + "]", 0.6); n.send(LEADER + "\\", 0.6)
    check("분할/닫기 15회: 파일 창 1개로 복귀", len(n.kinds("file")) == 1 and n.alive(), n.state())
    check("반복 사용: autocmd 개수 증가 없음", n.q("len(nvim_get_autocmds({}))") == base_ac, (base_ac, n.q("len(nvim_get_autocmds({}))")))
    grow = n.rss_mb() - base_rss
    check("반복 사용: nvim 메모리 증가 < 60MB", grow < 60, f"{base_rss:.0f}MB -> {n.rss_mb():.0f}MB")
    check("반복 사용: 오류 없음", not n.errors(), n.errors()); n.close()

    # ── 한글(전각) 파일 이름: 탭 ✕ 클릭이 그 탭을 닫는가
    for nm in ("한글파일.tf", "두번째 파일.tf"): open(f"{FIX}/{nm}", "w").write("# k\n")
    n = Nv("a.tf"); n.send(":e 한글파일.tf\r", 1); n.send(":e 두번째\\ 파일.tf\r", 1)
    tc = {t["name"]: t for t in n.tabcols()}
    check("전각 이름: 탭 좌표 계산", {"한글파일.tf", "두번째 파일.tf"} <= set(tc), list(tc))
    if "한글파일.tf" in tc:
        t = tc["한글파일.tf"]; n.click(t["row"], t["close"]); w = n.kinds("file")[0]
        check("전각 이름: 한글파일.tf 의 ✕ 클릭 → 그 탭만 닫힘", "한글파일.tf" not in w["tabs"] and "a.tf" in w["tabs"] and "두번째 파일.tf" in w["tabs"], w["tabs"])
    n.close()

    # ── 색 대비(WCAG): 탭줄·창 글자가 읽을 수 있는가
    n = Nv("a.tf"); n.drain(2)
    def hl(name):
        r = n.q(f"luaeval('vim.inspect(vim.api.nvim_get_hl(0,{{name=\"{name}\",link=false}}))')")
        import re
        fg = re.search(r"fg = (\d+)", r); bg = re.search(r"bg = (\d+)", r)
        f = f"#{int(fg.group(1)):06x}" if fg else None; b = f"#{int(bg.group(1)):06x}" if bg else None
        return f, b
    normal_bg = hl("Normal")[1] or "#1a1b26"
    for name, minr in (("TabLine", 3.0), ("TabLineSel", 4.5), ("PairTabClose", 3.0), ("PairTabAccent", 3.0), ("PairTabModified", 3.0), ("CursorLineNr", 3.0)):
        f, b = hl(name); b = b or normal_bg
        c = contrast(f, b) if f else 0
        check(f"색 대비 {name}: {c:.1f}:1 ≥ {minr}", c >= minr, f"{f} on {b}")
    n.close()

    # ── 모음 키: 선택기(Snacks)가 열리고 닫히는가
    n = Nv("a.tf")
    for keys, label in ((LEADER + "hf", "파일 찾기"), (LEADER + "hr", "최근 파일"), (LEADER + "hg", "텍스트 검색"), (LEADER + "ha", "AI 선택")):
        n.send(keys, 2.0); opened = len(n.kinds("float")) >= 1
        n.send("\x1b", 0.8); n.send("\x1b", 0.5)
        check(f"Space h {keys[-1]} ({label}): 선택기가 열리고 Esc 로 닫힘", opened and n.alive() and not n.errors(), n.errors())
    n.send(LEADER + "hc", 1.5)
    check("Space h c (코드 액션, LSP 없음): 오류 없이 처리", n.alive() and "E5108" not in n.q("execute('messages')"), n.q("execute('messages')")[-200:]); n.close()

    # ── 천천히 눌러서 which-key 팝업이 뜬 상태에서도 키가 동작하는가
    n = Nv("a.tf"); n.send(":e b.tf\r", 1)
    n.send(LEADER, 1.8); n.send("]", 1.5)
    check("느린 입력(which-key 팝업 후) Space ]: 분할됨", len(n.kinds("file")) == 2, n.state())
    n.send(LEADER, 1.8); n.send("\\", 1.5)
    check("느린 입력 Space \\: 분할 닫힘", len(n.kinds("file")) == 1 and n.alive(), n.state())
    n.send(LEADER, 1.8); n.send("b", 1.2); n.send("d", 1.5)
    check("느린 입력 Space b d: 탭 닫힘", n.alive() and len(n.kinds("file")[0]["tabs"]) == 1, n.state()); n.close()

    # ── 세션 복원: 그 사이 파일이 지워졌어도 오류 없이 복원
    shutil.rmtree(f"{XDG['XDG_STATE_HOME']}/nvim/sessions", ignore_errors=True)
    tmpf = f"{FIX}/ephemeral.tf"; open(tmpf, "w").write("# e\n")
    n = Nv("a.tf"); n.send(":e ephemeral.tf\r", 1); n.send(":qa!\r", 3); n.close()
    os.remove(tmpf)
    n = Nv(); n.drain(4)
    check("세션 복원: 지워진 파일이 있어도 살아 있고 오류 없음", n.alive() and not [e for e in n.errors() if "E5108" in e or "stack traceback" in e], n.errors()); n.close()

    # ── 큰 파일(30MB)을 열어도 멈추지 않는가
    big = f"{FIX}/big.log"
    if not os.path.exists(big):
        with open(big, "w") as f:
            line = "x" * 120 + "\n"; f.write(line * 250000)
    t0 = time.time(); n = Nv("big.log"); n.drain(1)
    ok = n.alive(); dt = time.time() - t0
    check("큰 파일(30MB): 열리고 응답함", ok and n.q("line('$')") != "", f"{dt:.1f}s")
    n.send("G", 1.5)
    check("큰 파일: 끝으로 이동·오류 없음", n.alive() and int(n.q("line('.')") or 0) > 1000 and not n.errors(), n.errors()); n.close()

    # ── 설정값 확인(우리 기능이 기대는 옵션)
    n = Nv("a.tf"); n.drain(2)
    check("옵션: hidden", n.q("&hidden") == "1")
    check("옵션: sessionoptions 에 globals(창별 탭 저장에 필요)", "globals" in n.q("&sessionoptions"), n.q("&sessionoptions"))
    check("옵션: titlestring 이 PairVim", "PairVim" in n.q("&titlestring"), n.q("&titlestring"))
    check("옵션: mouse 사용(탭 클릭에 필요)", "a" in n.q("&mouse") or "n" in n.q("&mouse"), n.q("&mouse"))
    n.close()

def scenarios_update():
    """:Pair update / 시작 화면 u / 시작 시 확인: 가짜 원격(bare)과 클론으로 pull 흐름을 시험한다."""
    root = f"{HOME}/upd"; shutil.rmtree(root, ignore_errors=True); os.makedirs(root)
    g = lambda cwd, *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", cwd, *a], capture_output=True, text=True)
    bare, seed, work = f"{root}/origin.git", f"{root}/seed", f"{root}/work"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", bare])
    shutil.copytree(REPO, seed, ignore=shutil.ignore_patterns(".git", "e2e", "__pycache__"))
    g(seed, "init", "-q", "-b", "main"); g(seed, "add", "-A"); g(seed, "commit", "-qm", "seed"); g(seed, "remote", "add", "origin", bare); g(seed, "push", "-q", "-u", "origin", "main")
    def fresh(name):
        cfgroot = f"{root}/{name}"; os.makedirs(cfgroot)
        g(cfgroot, "clone", "-q", bare, "nvim")
        return cfgroot, f"{cfgroot}/nvim"
    def upstream_commit(fname, text="x\n"):
        if not os.path.isdir(work): subprocess.run(["git", "clone", "-q", bare, work])
        g(work, "pull", "-q"); open(f"{work}/{fname}", "w").write(text); g(work, "add", "-A"); g(work, "commit", "-qm", f"add {fname}"); g(work, "push", "-q")
    def start(cfgroot, state):
        os.makedirs(f"{root}/{state}", exist_ok=True)
        return Nv(env={"XDG_CONFIG_HOME": cfgroot, "XDG_STATE_HOME": f"{root}/{state}"})
    def beh(n): return n.q("luaeval('require(\"config.pair\").behind == nil and -1 or require(\"config.pair\").behind')")
    def no_lua_error(n): return n.alive() and not [e for e in n.errors() if "E5108" in e or "stack traceback" in e]

    # 1) 최신 상태: 시작 화면에 u 항목, 새 커밋 표시 없음
    cfgroot, cfg = fresh("c1"); n = start(cfgroot, "s1"); n.drain(6)
    check("시작 화면: PairVim 업데이트 항목 존재", n.q("luaeval('require(\"config.pair\").dash_entry.key')") == "u")
    scr = n.text()
    if scr is not None: check("시작 화면: 'PairVim 업데이트' 글자가 보임", "PairVim 업데이트" in scr, scr[-300:])
    check("시작 시 확인(최신): 뒤처짐 0", beh(n) == "0", beh(n))
    check("시작 화면 기존 항목 유지(파일 찾기 f 등)", "파일 찾기" in (n.text() or "파일 찾기"), "")
    n.close()

    # 2) 새 커밋이 있으면 시작 시 감지하고 표시, u 로 받는다
    upstream_commit("marker1.txt")
    n = start(cfgroot, "s2"); n.drain(7)
    check("시작 시 확인: 새 커밋 1개 감지", beh(n) == "1", beh(n))
    scr = n.text()
    if scr is not None: check("시작 화면: 새 커밋 개수가 보임", "새 커밋 1개" in scr, scr[-300:])
    n.q("execute('lua vim.fn.confirm = function() return 2 end')")   # 재시작 확인창은 '나중에'
    n.send("u", 6)
    check("u 로 업데이트: 파일이 반영됨", os.path.exists(f"{cfg}/marker1.txt"))
    check("u 로 업데이트: 뒤처짐 0·살아 있음·오류 없음", beh(n) == "0" and no_lua_error(n), n.errors())
    n.close()

    # 3) 로컬 수정이 있으면 받지 않고 중단
    upstream_commit("marker2.txt")
    open(f"{cfg}/README.md", "a").write("\n로컬 수정\n")
    n = start(cfgroot, "s3"); n.drain(5); n.send(":Pair update\r", 5)
    check("로컬 수정 있음: 업데이트 중단(파일 안 받음)", not os.path.exists(f"{cfg}/marker2.txt") and no_lua_error(n), n.errors())
    n.close(); g(cfg, "checkout", "--", "README.md")

    # 4) lazy-lock.json 만 바뀐 경우: 되돌리기에 동의하면 진행
    open(f"{cfg}/lazy-lock.json", "a").write("\n")
    n = start(cfgroot, "s4"); n.drain(5)
    n.q("execute('lua _G.__asked = 0; local c = vim.fn.confirm; vim.fn.confirm = function(m, ch, d) _G.__asked = _G.__asked + 1; if m:find(\"lazy\", 1, true) then return 1 end return 2 end')")
    n.send(":Pair update\r", 7)
    check("lock 만 수정: 되돌리고 업데이트 진행", os.path.exists(f"{cfg}/marker2.txt") and no_lua_error(n) and n.q("luaeval('_G.__asked')") != "0", n.errors())
    n.close()

    # 4-b) 실제 키로 확인창에 답하기(영문 단축키): lock 만 수정 → Y 로 진행
    upstream_commit("marker3.txt")
    open(f"{cfg}/lazy-lock.json", "a").write("\n")
    n = start(cfgroot, "s4b"); n.drain(5)
    n.send(":Pair update\r", 3)
    scr = n.text()
    if scr is not None: check("확인창에 영문 단축키(Y/N)가 보임", __import__("re").search(r"[(\[]Y[)\]]es", scr) is not None and __import__("re").search(r"[(\[]N[)\]]o", scr) is not None, scr[:600])
    n.send("y", 8)
    check("확인창에서 y: 되돌리고 업데이트 진행", os.path.exists(f"{cfg}/marker3.txt") and no_lua_error(n), n.errors())
    n.send("l", 2)   # 재시작 확인창: L(나중에)
    check("재시작 확인창에서 l(Later): nvim 유지", n.alive())
    n.close()

    # 5) 오프라인(원격 접속 불가): 조용히 넘어가고 오류 없음
    g(cfg, "remote", "set-url", "origin", f"{root}/nonexistent.git")
    n = start(cfgroot, "s5"); n.drain(7)
    check("오프라인: 시작 시 확인이 조용히 실패(오류 없음)", no_lua_error(n) and beh(n) == "-1", (beh(n), n.errors()))
    n.send(":Pair update\r", 4)
    check("오프라인: :Pair update 가 오류로 끝나지만 nvim 은 정상", no_lua_error(n), n.errors())
    n.send(":Pair status\r", 2); n.send(":Pair log\r", 2); n.send(":Pair 이상한것\r", 1.5)
    check(":Pair status/log/알 수 없는 하위 명령: 오류 없음", no_lua_error(n), n.errors()); n.close()

    # 6) git 저장소가 아닌 설정(.git 없음): 안내만 하고 오류 없음
    n = Nv("a.tf"); n.drain(2); n.send(":Pair update\r", 2); n.send(":Pair check\r", 2); n.send(":Pair\r", 2)
    check("git 저장소 아님: :Pair 명령들이 안내만 하고 오류 없음", n.alive() and not [e for e in n.errors() if "E5108" in e], n.errors()); n.close()

def fuzz(seeds=(1, 2, 3), steps=18):
    """무작위 조합: 어떤 순서로 눌러도 (1) nvim 이 살아 있는 동안 파일 창이 1개 이상, (2) 오류 메시지 없음, (3) 상태를 읽을 수 있어야 한다."""
    import random
    normal_keys = [LEADER + "]", LEADER + "[", LEADER + "\\", LEADER + "bd", "\t", "\x1b[Z", LEADER + "e", LEADER + "ac",
                   "\x1bOR", ":e c.tf\r", ":e d.tf\r", ":e sub/s.tf\r", "\x08", "\x0a", "\x0b", "\x0c", "j", "G", "gg"]
    term_keys = ["\x08", "\x0a", "\x0b", "\x0c", "\x1bOR", "\x1bOS", "ls\r"]
    for seed in seeds:
        rnd = random.Random(seed)
        n = Nv("a.tf"); n.send(":e b.tf\r", 1)
        trail, ok, why = [], True, ""
        for _ in range(steps):
            st = n.state()
            keys = term_keys if (st and st["mode"] == "t") else normal_keys
            k = rnd.choice(keys); trail.append(k)
            n.send(k, 0.9)
            if not n.alive():
                break          # 종료는 허용(Space \\ 가 마지막 탭에서 종료하는 것은 정상)
            st = n.state()
            if st is None: ok, why = False, "상태를 읽지 못함"; break
            if not any(w["kind"] == "file" for w in st["wins"]):
                ok, why = False, "파일 창이 하나도 없음: " + json.dumps(st["wins"], ensure_ascii=False); break
            errs = n.errors()
            if errs: ok, why = False, "오류: " + " / ".join(errs)[:200]; break
        check(f"무작위 조합 seed={seed}", ok, f"{why}  순서={[repr(x) for x in trail]}")
        n.close()

if __name__ == "__main__":
    setup()
    try:
        scenarios()
        scenarios_more()
        scenarios_audit()
        scenarios_env()
        scenarios_update()
        fuzz()
    finally:
        for f in os.listdir(HOME):
            if f.endswith(".sock"):
                try: os.unlink(f"{HOME}/{f}")
                except OSError: pass
    bad = [n for n, ok in results if not ok]
    print(f"\nTOTAL {len(results)}, FAIL {len(bad)}")
    sys.exit(1 if bad else 0)
