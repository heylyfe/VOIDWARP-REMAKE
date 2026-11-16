#!/usr/bin/env python
"""Gallery harness for VOIDWARP terrain reference levels.

Usage:
    python gallery.py --write    # write terrain_ref/gallery.json
    python gallery.py --check    # verify gallery.json against fresh generation
    python gallery.py --render   # render all 16 gallery PNGs into terrain_ref/out/
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voidgen  # noqa: E402
import render  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GALLERY_JSON = os.path.join(HERE, 'gallery.json')
OUT_DIR = os.path.join(HERE, 'out')

GALLERY = [(1, 1), (2, 1), (3, 1), (1001, 2), (1002, 3), (1003, 4), (1004, 5), (1005, 8),
           (1006, 10), (1007, 12), (7, 12), (1008, 16), (1009, 20), (1010, 25), (7, 30),
           (1011, 40)]


def build_record(seed, level):
    L = voidgen.generate(seed, level)
    rec = {
        'seed': seed,
        'level': level,
        'hash': voidgen.level_hash(L),
        'attempt': L['attempt'],
        'platforms': sum(1 for p in L['pieces'] if p['kind'] == 0) - 1,
        'tiles': len(L['tiles']),
        'slots': len(L['gifts']),
        'mines': sum(g['occ'] for g in L['gifts']),
        'loops': sum(1 for p in L['pieces'] if p['role'] == 4),
        'drops': sum(1 for p in L['pieces'] if p['role'] == 5),
        'pads': len(L['pads']),
        'arms': list(L['arms']),
        'dead_ends': sum(1 for p in L['pieces'] if p['role'] == 2),
    }
    assert rec['slots'] == voidgen.slot_target(level, 1), \
        f'seed={seed} level={level}: slots {rec["slots"]} != slot_target {voidgen.slot_target(level, 1)}'
    if level < 5:
        assert rec['mines'] == 0, f'seed={seed} level={level}: mines {rec["mines"]} != 0 for level < 5'
    assert rec['mines'] <= rec['slots'] // 5, \
        f'seed={seed} level={level}: mines {rec["mines"]} > slots//5 ({rec["slots"] // 5})'
    return rec


def build_records():
    return [build_record(seed, level) for seed, level in GALLERY]


def fmt(v):
    return str(v)


def cmd_write():
    records = build_records()
    with open(GALLERY_JSON, 'w', newline='\n') as f:
        json.dump(records, f, indent=1)
    print(f'wrote {GALLERY_JSON} ({len(records)} records)')
    return 0


def cmd_check():
    if not os.path.exists(GALLERY_JSON):
        print(f'missing {GALLERY_JSON}; run --write first')
        return 1
    with open(GALLERY_JSON, 'r', newline='\n') as f:
        stored = json.load(f)
    by_key = {}
    for entry in stored:
        by_key[(entry.get('seed'), entry.get('level'))] = entry

    ok_count = 0
    for seed, level in GALLERY:
        rec = build_record(seed, level)
        expected = by_key.get((seed, level))
        diffs = []
        if expected is None:
            diffs.append(('entry', '<missing>', 'present'))
        else:
            for key, got in rec.items():
                if key not in expected:
                    diffs.append((key, '<missing>', got))
                elif expected[key] != got:
                    diffs.append((key, expected[key], got))
        if diffs:
            for key, exp, got in diffs:
                print(f'DIFF seed={seed} level={level} field={key} expected={fmt(exp)} got={fmt(got)}')
        else:
            ok_count += 1
            print(f'OK seed={seed} level={level}')
    print(f'GALLERY {ok_count}/{len(GALLERY)} OK')
    return 0 if ok_count == len(GALLERY) else 1


def cmd_render():
    os.makedirs(OUT_DIR, exist_ok=True)
    for i, (seed, level) in enumerate(GALLERY, 1):
        L = voidgen.generate(seed, level)
        path = os.path.join(OUT_DIR, f'gallery_{i:02d}_seed{seed}_level{level}.png')
        render.render(L, path, 6)
        print(f'wrote {path}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description='VOIDWARP gallery harness.')
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument('--write', action='store_true')
    group.add_argument('--check', action='store_true')
    group.add_argument('--render', action='store_true')
    args = ap.parse_args(argv)
    if args.write:
        return cmd_write()
    if args.check:
        return cmd_check()
    return cmd_render()


if __name__ == '__main__':
    sys.exit(main())
