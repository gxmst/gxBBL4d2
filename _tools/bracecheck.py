#!/usr/bin/env python3
"""Lightweight Squirrel structural sanity check.

NOT a parser. Catches the low-level breakage the truncated-write session hit:
unbalanced (), {}, [], and unterminated "..." strings. Handles // and /* */
comments and \\-escapes inside strings. Reports first offending line.
"""
import sys

def check(path):
    src = open(path, encoding="utf-8").read()
    stack = []  # (char, line)
    pairs = {')': '(', ']': '[', '}': '{'}
    opens = set("([{")
    line = 1
    i = 0
    n = len(src)
    in_str = False
    str_ch = ""
    str_line = 0
    in_line_comment = False
    in_block_comment = False
    errors = []
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "\n":
            line += 1
            if in_line_comment:
                in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == str_ch:
                in_str = False
            i += 1
            continue
        # not in string/comment
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if c == '"' or c == "'":
            in_str = True
            str_ch = c
            str_line = line
            i += 1
            continue
        if c in opens:
            stack.append((c, line))
        elif c in pairs:
            if not stack:
                errors.append(f"line {line}: unmatched closing '{c}'")
            else:
                op, ol = stack.pop()
                if op != pairs[c]:
                    errors.append(
                        f"line {line}: '{c}' closes '{op}' opened at line {ol}")
        i += 1
    if in_str:
        errors.append(f"line {str_line}: unterminated string")
    if in_block_comment:
        errors.append("EOF: unterminated /* */ block comment")
    for op, ol in stack:
        errors.append(f"line {ol}: unclosed '{op}'")
    errors.extend(check_reserved(src))
    return errors

# Squirrel reserved words that silently break a whole file if used as a local
# or parameter name (brace-balanced, so the structural scan above misses them).
# 'base' is the one DESIGN 7.3 warns about; the rest are the same class of trap.
RESERVED = {
    "base", "this", "constructor", "delete", "typeof", "instanceof",
    "in", "clone", "class", "function", "local", "return", "if", "else",
    "while", "for", "foreach", "switch", "case", "default", "break",
    "continue", "null", "true", "false", "static", "enum", "const",
    "try", "catch", "throw", "yield", "resume", "extends",
}

def _strip_code(src):
    """Return src with string/comment contents blanked (newlines kept) so a
    regex scan can't match reserved words inside them."""
    out = []
    i, n = 0, len(src)
    in_str = False; str_ch = ""; in_lc = False; in_bc = False
    while i < n:
        c = src[i]; nxt = src[i + 1] if i + 1 < n else ""
        if in_lc:
            if c == "\n": in_lc = False; out.append(c)
            else: out.append(" ")
            i += 1; continue
        if in_bc:
            if c == "*" and nxt == "/": in_bc = False; out.append("  "); i += 2; continue
            out.append("\n" if c == "\n" else " "); i += 1; continue
        if in_str:
            if c == "\\": out.append("  "); i += 2; continue
            if c == str_ch: in_str = False
            out.append("\n" if c == "\n" else " "); i += 1; continue
        if c == "/" and nxt == "/": in_lc = True; out.append("  "); i += 2; continue
        if c == "/" and nxt == "*": in_bc = True; out.append("  "); i += 2; continue
        if c == '"' or c == "'": in_str = True; str_ch = c; out.append(" "); i += 1; continue
        out.append(c); i += 1
    return "".join(out)

def check_reserved(src):
    import re
    code = _strip_code(src)
    errors = []
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*)", code):
        if m.group(1) in RESERVED:
            ln = code.count("\n", 0, m.start()) + 1
            errors.append(f"line {ln}: reserved word '{m.group(1)}' used as local")
    # function/param lists: function Name(a, b, base) { ... }
    for m in re.finditer(r"function[^(]*\(([^)]*)\)", code):
        params = m.group(1)
        for raw in params.split(","):
            name = raw.strip().split("=")[0].strip()
            if name in RESERVED:
                ln = code.count("\n", 0, m.start()) + 1
                errors.append(f"line {ln}: reserved word '{name}' used as parameter")
    return errors

if __name__ == "__main__":
    total = 0
    for p in sys.argv[1:]:
        errs = check(p)
        if errs:
            total += len(errs)
            print(f"[FAIL] {p}")
            for e in errs[:20]:
                print("   " + e)
        else:
            print(f"[ok]   {p}")
    sys.exit(1 if total else 0)
