#!/usr/bin/env python3
"""Prints one row per device run from the files mac.sh test copies to build/mac/.

    python ios/scripts/summarize-runs.py build/mac/stream-*.txt

Each row comes from the run's last "Pacing summary" line (the whole stream) plus the overlay's
network latency and decode time at the end, so A/B runs can be compared side by side.
"""

import re
import sys


def field(pattern, text, default='-'):
    m = re.search(pattern, text)
    return m.group(1) if m else default


def summarize(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    summaries = re.findall(r'\[device-run\] summary: (.*)', text)
    if not summaries:
        return None
    s = summaries[-1]
    samples = re.findall(r'Average network latency: (\d+) ms \(variance: (\d+) ms\)', text)
    decode = re.findall(r'Decode time: [\d.]+/[\d.]+/([\d.]+) ms', text)
    return {
        'run': path.replace('\\', '/').split('/')[-1].rsplit('.', 1)[0],
        'presenter': field(r'Pacing summary \((\w+)\)', s),
        'seconds': field(r': (\d+) s, in', s),
        'drops %': field(r'drops ([\d.]+)%', s),
        'shown 8.3 %': field(r'shown for [^:]+: [\d.]+/([\d.]+)/', s),
        'max shown ms': field(r'mean [\d.]+ ms, max ([\d.]+) ms, off grid', s),
        '1% low': field(r'1% low \(worst 5 s\) ([\d.]+) FPS', s),
        'no new frame %': field(r'refreshes without a new frame ([\d.]+)%', s),
        'net gaps': field(r'network gaps (\d+)', s),
        'max net gap ms': field(r'network gaps \d+, max ([\d.]+) ms', s),
        'gap period': field(r'every (\S+ ms)', s),
        'host gaps': field(r'host gaps (\d+)', s),
        'decode to screen ms': field(r'decode to screen mean ([\d.]+) ms', s),
        'network to screen ms': field(r'network to screen mean ([\d.]+) ms', s),
        'jitter held': field(r'held mean ([\d.]+)', s),
        'catch up': field(r'catch up (\d+)', s),
        'latency ms (last)': samples[-1][0] if samples else '-',
        'variance ms (max)': str(max(int(v) for _, v in samples[1:])) if len(samples) > 1 else '-',
        'decode ms (last)': decode[-1] if decode else '-',
    }


def main(paths):
    rows = [r for r in (summarize(p) for p in paths) if r]
    if not rows:
        print('no summaries found')
        return 1
    keys = list(rows[0].keys())
    print('| ' + ' | '.join(keys) + ' |')
    print('|' + '---|' * len(keys))
    for r in rows:
        print('| ' + ' | '.join(r[k] for k in keys) + ' |')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
