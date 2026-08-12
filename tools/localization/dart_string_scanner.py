#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class DartStringLiteral:
    start: int
    end: int
    content_start: int
    content_end: int
    line: int
    token: str
    body: str


def _is_identifier_char(ch: str) -> bool:
    return ch.isalnum() or ch == '_'


def _raw_prefix_start(text: str, quote_index: int) -> int:
    if quote_index <= 0 or text[quote_index - 1] not in ('r', 'R'):
        return quote_index
    before = text[quote_index - 2] if quote_index >= 2 else ''
    if before and _is_identifier_char(before):
        return quote_index
    return quote_index - 1


def _skip_comment(text: str, i: int) -> int:
    n = len(text)
    if text.startswith('//', i):
        newline = text.find('\n', i + 2)
        return n if newline < 0 else newline
    if text.startswith('/*', i):
        end = text.find('*/', i + 2)
        return n if end < 0 else end + 2
    return i


def _scan_string_end(text: str, quote_index: int, *, raw: bool) -> int:
    """Returns the exclusive end of a Dart string beginning at quote_index."""
    n = len(text)
    quote = text[quote_index]
    triple = text.startswith(quote * 3, quote_index)
    delimiter = quote * (3 if triple else 1)
    i = quote_index + len(delimiter)

    while i < n:
        if text.startswith(delimiter, i):
            return i + len(delimiter)
        ch = text[i]
        if not raw and ch == '\\':
            i += 2
            continue
        if not triple and ch in '\r\n':
            # Invalid/incomplete source; stop rather than consuming another line.
            return i
        if not raw and ch == '$' and i + 1 < n and text[i + 1] == '{':
            i = _skip_interpolation_expression(text, i + 2)
            continue
        i += 1
    return n


def _skip_interpolation_expression(text: str, i: int) -> int:
    """Skips from just after `${` through its balanced closing `}`."""
    n = len(text)
    depth = 1
    while i < n and depth > 0:
        skipped = _skip_comment(text, i)
        if skipped != i:
            i = skipped
            continue
        ch = text[i]
        if ch in ("'", '"'):
            token_start = _raw_prefix_start(text, i)
            raw = token_start < i
            i = _scan_string_end(text, i, raw=raw)
            continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
        elif ch == '\\':
            i += 2
            continue
        i += 1
    return i


def scan_dart_string_literals(text: str) -> list[DartStringLiteral]:
    values: list[DartStringLiteral] = []
    n = len(text)
    i = 0
    line = 1

    while i < n:
        skipped = _skip_comment(text, i)
        if skipped != i:
            line += text.count('\n', i, skipped)
            i = skipped
            continue

        ch = text[i]
        if ch not in ("'", '"'):
            if ch == '\n':
                line += 1
            i += 1
            continue

        token_start = _raw_prefix_start(text, i)
        raw = token_start < i
        quote = ch
        triple = text.startswith(quote * 3, i)
        delimiter_len = 3 if triple else 1
        end = _scan_string_end(text, i, raw=raw)
        if end <= i + delimiter_len:
            i += 1
            continue
        content_start = i + delimiter_len
        content_end = end - delimiter_len
        token = text[token_start:end]
        body = text[content_start:content_end]
        values.append(
            DartStringLiteral(
                start=token_start,
                end=end,
                content_start=content_start,
                content_end=content_end,
                line=line,
                token=token,
                body=body,
            )
        )
        line += text.count('\n', i, end)
        i = end

    return values
