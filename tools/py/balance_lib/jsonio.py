"""Strict JSON reader with line numbers, duplicate-key detection and decimal-place tracking (rules V-SCH-02 / V-SCH-04).

parse(text) -> (value, problems).  Objects are LDict (dict + .lines[key] + .decs[key]), arrays are LList (list + .lines[i] + .decs[i]).
`.line` is the line of the opening bracket, `.decs[k]` is the number of decimals of a numeric literal (absent for non-numbers/ints).
problems = [(line, rule, message)] -- duplicate keys, NaN/Infinity, syntax errors (parsing stops at the first syntax error).
"""
from __future__ import annotations


class LDict(dict):
    def __init__(self) -> None:
        super().__init__()
        self.lines: dict[str, int] = {}
        self.decs: dict[str, int] = {}
        self.line = 1


class LList(list):
    def __init__(self) -> None:
        super().__init__()
        self.lines: list[int] = []
        self.decs: dict[int, int] = {}
        self.line = 1


class _Err(Exception):
    def __init__(self, line: int, msg: str) -> None:
        super().__init__(msg)
        self.line, self.msg = line, msg


_WS = " \t\r\n"
_ESC = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}


class _P:
    def __init__(self, s: str) -> None:
        self.s, self.i, self.line, self.problems = s, 0, 1, []

    def ws(self) -> None:
        s, n = self.s, len(self.s)
        while self.i < n and s[self.i] in _WS:
            if s[self.i] == "\n":
                self.line += 1
            self.i += 1

    def err(self, msg: str) -> _Err:
        return _Err(self.line, msg)

    def value(self):
        self.ws()
        if self.i >= len(self.s):
            raise self.err("unexpected end of file")
        c = self.s[self.i]
        if c == "{":
            return self.obj()
        if c == "[":
            return self.arr()
        if c == '"':
            return self.string()
        for lit, val in (("true", True), ("false", False), ("null", None)):
            if self.s.startswith(lit, self.i):
                self.i += len(lit)
                return val
        for lit in ("NaN", "Infinity", "-Infinity"):
            if self.s.startswith(lit, self.i):
                self.problems.append((self.line, "V-SCH-04", f"non-finite number literal {lit}"))
                self.i += len(lit)
                return 0
        return self.number()

    def number(self):
        s, j = self.s, self.i
        n = len(s)
        if j < n and s[j] == "-":
            j += 1
        st = j
        while j < n and s[j].isdigit():
            j += 1
        if j == st:
            raise self.err(f"unexpected character {s[self.i]!r}")
        if s[st] == "0" and j - st > 1:
            raise self.err("leading zero in number")
        isf, decs = False, 0
        if j < n and s[j] == ".":
            isf = True
            k = j + 1
            while k < n and s[k].isdigit():
                k += 1
            if k == j + 1:
                raise self.err("digit expected after decimal point")
            decs = k - j - 1
            j = k
        if j < n and s[j] in "eE":
            isf = True
            k = j + 1
            if k < n and s[k] in "+-":
                k += 1
            k0 = k
            while k < n and s[k].isdigit():
                k += 1
            if k == k0:
                raise self.err("digit expected in exponent")
            j = k
        text = s[self.i:j]
        self.i = j
        self._decs = decs
        return float(text) if isf else int(text)

    def string(self) -> str:
        s, n = self.s, len(self.s)
        i = self.i + 1
        out = []
        while True:
            if i >= n:
                raise self.err("unterminated string")
            c = s[i]
            if c == '"':
                self.i = i + 1
                return "".join(out)
            if c == "\n":
                raise self.err("newline inside string")
            if c == "\\":
                i += 1
                e = s[i:i + 1]
                if e == "u":
                    out.append(chr(int(s[i + 1:i + 5], 16)))
                    i += 5
                    continue
                if e not in _ESC:
                    raise self.err("bad escape")
                out.append(_ESC[e])
                i += 1
                continue
            out.append(c)
            i += 1

    def obj(self) -> LDict:
        d = LDict()
        d.line = self.line
        self.i += 1
        self.ws()
        if self.s[self.i:self.i + 1] == "}":
            self.i += 1
            return d
        while True:
            self.ws()
            if self.s[self.i:self.i + 1] != '"':
                raise self.err("object key (string) expected")
            kline = self.line
            k = self.string()
            self.ws()
            if self.s[self.i:self.i + 1] != ":":
                raise self.err("':' expected")
            self.i += 1
            self._decs = 0
            v = self.value()
            if k in d:
                self.problems.append((kline, "V-SCH-02", f"duplicate key {k!r} in object (first at line {d.lines[k]})"))
            d[k] = v
            d.lines[k] = kline if k not in d.lines else d.lines[k]
            if self._decs and isinstance(v, float):
                d.decs[k] = self._decs
            self._decs = 0
            self.ws()
            c = self.s[self.i:self.i + 1]
            self.i += 1
            if c == ",":
                continue
            if c == "}":
                return d
            raise self.err("',' or '}' expected")

    def arr(self) -> LList:
        a = LList()
        a.line = self.line
        self.i += 1
        self.ws()
        if self.s[self.i:self.i + 1] == "]":
            self.i += 1
            return a
        while True:
            self.ws()
            ln = self.line
            self._decs = 0
            v = self.value()
            if self._decs and isinstance(v, float):
                a.decs[len(a)] = self._decs
            self._decs = 0
            a.append(v)
            a.lines.append(ln)
            self.ws()
            c = self.s[self.i:self.i + 1]
            self.i += 1
            if c == ",":
                continue
            if c == "]":
                return a
            raise self.err("',' or ']' expected")


def parse(text: str):
    """Return (value, problems). On a syntax error value is None and problems holds one 'V-SCH-01' entry."""
    p = _P(text)
    p._decs = 0
    try:
        v = p.value()
        p.ws()
        if p.i < len(text):
            raise p.err("trailing characters after top-level value")
    except _Err as e:
        p.problems.append((e.line, "V-SCH-01", f"invalid JSON: {e.msg}"))
        return None, p.problems
    except (IndexError, ValueError) as e:
        p.problems.append((p.line, "V-SCH-01", f"invalid JSON: {e}"))
        return None, p.problems
    return v, p.problems


def line_of(container, key) -> int:
    """Line of key in an LDict / index in an LList; falls back to the container's own line."""
    try:
        if isinstance(container, LDict):
            return container.lines.get(key, container.line)
        if isinstance(container, LList):
            return container.lines[key]
    except (IndexError, TypeError):
        pass
    return getattr(container, "line", 0)
