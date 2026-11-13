#!/usr/bin/env python3
"""PairVim e2e 시험: 가상 터미널(pty)에서 실제 nvim 을 켜고 키를 보내, 창 종류 × 동작 조합을 점검한다.

사용:  python3 tests/e2e/e2e.py            (nvim, git 필요. 플러그인은 격리 폴더에 처음 한 번 설치)
환경:  NVIM=nvim 경로, PV_E2E_HOME=작업 폴더(기본 /tmp/pairvim-e2e)
외부 서비스는 쓰지 않는다: claude/codex/terraform 은 가짜 스크립트로 대신한다.
시험은 "무엇이 일어나면 안 되는가"(불변식)를 확인한다. 고친 버그는 여기에 시나리오를 추가한다.
"""
import os, pty, select, signal, subprocess, sys, time, json, shutil, fcntl, termios, struct

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
    return e

class Nv:
    def __init__(self, *files):
        global SOCK
        _count[0] += 1
        SOCK = f"{HOME}/nvim-{os.getpid()}-{_count[0]}.sock"
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(FIX)
            os.execvpe(NVIM, [NVIM, "-n", "--listen", SOCK, *files], envs())   # -n: 강제 종료한 시험이 남긴 스왑 파일에 막히지 않게
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 150, 0, 0))
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
                try: os.read(self.fd, 65536)
                except OSError: return
    def send(self, s, t=0.7):
        os.write(self.fd, s.encode()); self.drain(t)
    def q(self, expr):
        r = subprocess.run([NVIM, "--server", SOCK, "--remote-expr", expr], capture_output=True, text=True, timeout=15)
        return r.stdout.strip()
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
        fuzz()
    finally:
        for f in os.listdir(HOME):
            if f.endswith(".sock"):
                try: os.unlink(f"{HOME}/{f}")
                except OSError: pass
    bad = [n for n, ok in results if not ok]
    print(f"\nTOTAL {len(results)}, FAIL {len(bad)}")
    sys.exit(1 if bad else 0)
