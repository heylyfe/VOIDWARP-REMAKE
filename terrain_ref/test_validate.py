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
    assert validate.run_selftest(), "selftest did not reach 12/12"

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
