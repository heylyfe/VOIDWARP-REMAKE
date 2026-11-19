"""Plain-assert tests for the VOIDWRAP terrain validator (spec 10).

Run: python test_validate.py   (no pytest; prints TESTS OK on success)
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import validate  # noqa: E402
from voidgen import generate, mine_chance_num, slot_target  # noqa: E402


def main():
    # D1 exact table
    assert mine_chance_num(4) == 0
    assert mine_chance_num(5) == 20
    assert mine_chance_num(15) == 30
    assert mine_chance_num(25) == 40
    assert mine_chance_num(26) == 40
    assert mine_chance_num(99) == 40

    # slot targets
    assert slot_target(1, 1) == 40
    assert slot_target(30, 1) == 156
    assert slot_target(31, 1) == 160
    assert slot_target(99, 1) == 160

    # planted-defect selftest
    assert validate.run_selftest(), "selftest did not reach 18/18"

    # tripmine bypass (TERRAIN_SPEC 6.8): the contact test is integer-only and symmetric
    assert validate.seg_hits_mine(0, 0, 2, 0, 1, 0), "a mine on the segment is not detected"
    assert not validate.seg_hits_mine(0, 0, 2, 0, 1, 1), "a mine 1.0 u off the segment is detected"
    assert validate.seg_hits_mine(0, 0, 2, 0, 0, 0), "a mine on an endpoint is not detected"
    assert not validate.seg_hits_mine(0, 0, 2, 0, 3, 0), "a mine 1.0 u past the endpoint is detected"
    # every mine of every generated level has a walkable bypass, and the joint rule holds
    for s in range(1, 21):
        L = generate(s, 1 + (s % 30))
        base = validate.walk_layer(L)
        adj = validate.build_adj(L, base, validate.VALIDATOR_GAP)
        judge = validate.MineJudge(base, adj)
        mines = []
        for g in L["gifts"]:
            t = validate.find_tile(base, g["x"], g["z"], g["y"])
            if g["occ"]:
                assert t >= 0 and judge.eligible(t), \
                    "seed %d level %d: mine slot %d has no walkable bypass" % (s, L["level"], g["id"])
                mines.append(t)
        if mines:
            assert judge.keeps_rt(mines), \
                "seed %d level %d: the mine set breaks the joint rule" % (s, L["level"])

    # footprint similarity (TERRAIN_SPEC 10.3): anchored to the spawn root, 8 symmetries
    import copy
    ft = generate(7, 9)
    fp8 = validate.footprints8(ft)
    assert fp8[0], "empty footprint"
    assert validate.similarity(fp8[0], fp8) == 1.0, "a level is not identical to itself"
    # a SHIFTED duplicate (every tile and the beacon moved) must still score 1.0
    sh = copy.deepcopy(ft)
    for t in sh["tiles"]:
        t[0] += 37
        t[1] -= 21
    sh["beacon"][0] += 37
    sh["beacon"][1] -= 21
    assert validate.similarity(fp8[0], validate.footprints8(sh)) == 1.0, "shifted duplicate not caught"
    # a rotated / mirrored duplicate must be flagged (>= 0.60) under every one of the 8 symmetries
    for k in range(8):
        tr = copy.deepcopy(ft)
        for t in tr["tiles"]:
            t[0], t[1] = validate.XFORMS[k](t[0], t[1])
        sk = validate.similarity(fp8[0], validate.footprints8(tr))
        assert sk >= 0.60, "transformed duplicate %d scored only %r" % (k, sk)
    assert validate.similarity(fp8[0], validate.footprints8(generate(8, 9))) < 0.60, "different seeds look alike"

    # seeds 1..20 at level 1 pass every hard check
    for s in range(1, 21):
        L = generate(s, 1)
        r = validate.check_level(L)
        assert not r["fails"], "seed %d: %r" % (s, r["fails"])

    print("TESTS OK")


if __name__ == "__main__":
    main()
