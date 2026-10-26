#!/usr/bin/env python3
# MSXPi Interface
# Version 1.6.1
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

"""link2.asm (sjasmplus/zmac syntax) as SDAS source for the C library.

The conditional assembly is evaluated, the macros expanded, every constant turned
into a number and every immediate operand given its '#'.  What comes out is the
same code the ROM and the asm tools assemble, so the C clients speak LINK2 with
the very routines the Python model (tests/link2_sim.py, class Msx) is the
reference for.
"""
import re

REGS = {'a', 'b', 'c', 'd', 'e', 'h', 'l', 'af', 'bc', 'de', 'hl', 'sp', 'ix', 'iy',
        'i', 'r', "af'", 'nz', 'z', 'nc', 'po', 'pe', 'p', 'm'}
NUMBER_FIRST = {'bit', 'set', 'res', 'im', 'rst'}
BRANCH = {'jp', 'jr', 'call', 'djnz'}
TABLE_PAGE = re.compile(r'^LINK_CRC_TABLE_HI\s*>>\s*8$')


def number(expr):
    """An assembler constant expression as Python source: $B2, 0FFh."""
    expr = re.sub(r'\$([0-9A-Fa-f]+)', r'0x\1', expr)
    return re.sub(r'\b([0-9][0-9A-Fa-f]*)[hH]\b', r'0x\1', expr).replace('/', '//')


def equs(text, env):
    """Evaluate every `NAME: EQU expr` of an assembler source into env."""
    for m in re.finditer(r'^([A-Za-z_]\w*):?\s+EQU\s+([^;\n]+)', text, re.M):
        try:
            env[m.group(1)] = eval(number(m.group(2).strip()), {}, env)
        except NameError:
            pass
    return env


def split_operands(text):
    out, depth, cur = [], 0, ''
    for ch in text:
        if ch == '(':
            depth += 1
        if ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def operand(mnemonic, index, op, env):
    low = op.lower()
    if low in REGS:
        return low
    if op.startswith('(') and op.endswith(')'):
        inner = op[1:-1].strip()
        m = re.match(r'(ix|iy)\s*([+-].*)?$', inner, re.I)
        if m:
            return '%d(%s)' % (eval(number(m.group(2) or '+0'), {}, env), m.group(1).lower())
        if inner.lower() in REGS:
            return '(%s)' % inner.lower()
        return '(0x%x)' % eval(number(inner), {}, env)
    if mnemonic in BRANCH:
        return op
    if mnemonic in NUMBER_FIRST and index == 0:
        return str(eval(number(op), {}, env))
    return '#0x%x' % (eval(number(op), {}, env) & 0xFFFF)


def sdas_lines(text, env, defined=()):
    macros, body, stack, out = {}, None, [], []
    for raw in text.split('\n'):
        line = raw.split(';')[0].rstrip()
        words = line.split()
        key = words[0].lower() if words else ''
        if key in ('ifdef', 'ifndef'):
            stack.append((words[1] in defined) == (key == 'ifdef'))
            continue
        if key == 'else':
            stack[-1] = not stack[-1]
            continue
        if key == 'endif':
            stack.pop()
            continue
        if not all(stack):
            continue
        if body is not None:
            if key == 'endm':
                body = None
            else:
                body.append(line)
            continue
        if len(words) > 1 and words[1].lower() == 'macro':
            macros[words[0]] = body = []
            continue
        if re.match(r'^[A-Za-z_]\w*:?\s+EQU\s', line, re.I) or key in ('include', 'defs', 'assert'):
            continue
        for item in (macros[words[0]] if words and words[0] in macros else [line]):
            label = re.match(r'^([A-Za-z_]\w*):', item)
            if label:
                out.append(label.group(1) + ':')
            parts = (item[label.end():] if label else item).strip().split(None, 1)
            if not parts:
                continue
            mnemonic = parts[0].lower()
            ops = split_operands(parts[1]) if len(parts) > 1 else []
            if mnemonic == 'ld' and len(ops) == 2 and TABLE_PAGE.match(ops[1].replace(' ', '')):
                # the CRC table is built in RAM at a page boundary (msxpi-bios.c)
                out.append('    ld a,(_l2_table_page)')
                out.append('    ld %s,a' % ops[0].lower())
                continue
            ops = [operand(mnemonic, i, o, env) for i, o in enumerate(ops)]
            out.append('    ' + mnemonic + (' ' + ','.join(ops) if ops else ''))
    return out


def link2_kernel(root, wait_and_escape):
    """The asm lines of the C library's LINK2: payload.z80's PAYLOAD_WAIT and
    PAYLOAD_ESCAPE (already SDAS), then link2.asm."""
    env = equs((root / 'asm-common/include/include.asm').read_text(), {})
    equs((root / 'asm-common/include/link2.asm').read_text(), env)
    code = sdas_lines((root / 'asm-common/include/link2.asm').read_text(), env)
    return '\n'.join([wait_and_escape] + code)
