"""Deterministic behavioral checks for the TTP229 reader and note chain.

This models the same edge order used by ttp229_serial16.v.  It is kept
dependency-free because the Gowin installation does not ship an HDL simulator.
"""
from math import isclose
from pathlib import Path

NOTE_TABLE = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84, 86]
PHASE_TABLE = [11312704, 12698081, 14253114, 15100648, 16949904, 19025624,
               21355541, 22625407, 25396161, 28506227, 30201296, 33899808,
               38051248, 42711082, 45250815, 50792322]


def lowest_note(keys: int):
    for i in range(16):
        if keys & (1 << i):
            return True, NOTE_TABLE[i]
    return False, 0


class Reader:
    """Frame-level equivalent of the RTL's two-identical-frame filter."""
    def __init__(self):
        self.candidate = 0
        self.stable = 0
        self.keys = 0

    def frame(self, raw: int):
        if raw == self.candidate:
            self.stable = min(3, self.stable + 1)
            if self.stable >= 1:
                self.keys = raw
        else:
            self.candidate = raw
            self.stable = 0
        return self.keys


def serial_bits(keys: int, active_low=True):
    # TTP229 sends D0..D15, corresponding to TP0..TP15.
    return [0 if (keys & (1 << i)) else 1 for i in range(16)] if active_low else \
           [1 if (keys & (1 << i)) else 0 for i in range(16)]


def check_serial_order():
    for key in range(16):
        bits = serial_bits(1 << key, active_low=True)
        assert bits[key] == 0
        assert sum(b == 0 for b in bits) == 1
    assert serial_bits(0) == [1] * 16
    assert serial_bits(0xFFFF).count(0) == 16


def check_filter_and_priority():
    r = Reader()
    assert r.frame(0) == 0
    assert r.frame(0) == 0
    assert r.frame(1 << 7) == 0
    assert r.frame(1 << 7) == (1 << 7)
    assert lowest_note((1 << 4) | (1 << 1)) == (True, 62)
    assert lowest_note(0) == (False, 0)
    # Rapid changes require two equal frames and never expose a random key.
    assert r.frame(1 << 12) == (1 << 7)
    assert r.frame(1 << 3) == (1 << 7)
    assert r.frame(1 << 3) == (1 << 3)


def check_pitch_table():
    assert len(NOTE_TABLE) == 16
    assert len(PHASE_TABLE) == 16
    for a, b in zip(PHASE_TABLE, PHASE_TABLE[1:]):
        assert b > a
    # The existing working A4 calibration is the reference.
    assert PHASE_TABLE[5] == 19025624
    for i, midi in enumerate(NOTE_TABLE):
        expected = 19025624 * 2 ** ((midi - 69) / 12)
        assert abs(PHASE_TABLE[i] - expected) <= 1.0


def check_envelope():
    gain = 0
    previous_note = None
    note_on = False
    step = 1024

    def tick(on, note):
        nonlocal gain, previous_note, note_on
        if on and (not note_on or note != previous_note):
            gain = 0
        elif on:
            gain = min(32767, gain + step)
        else:
            gain = max(0, gain - step)
        note_on, previous_note = on, note
        return gain

    assert tick(True, 60) == 0
    assert 0 < tick(True, 60) < 32767
    for _ in range(64):
        tick(True, 60)
    assert gain == 32767
    assert tick(True, 62) == 0
    assert tick(False, 62) == 0


def main():
    check_serial_order()
    check_filter_and_priority()
    check_pitch_table()
    check_envelope()
    print("PASS: TTP229 D0..D15 active-low serial order")
    print("PASS: no-touch, 16 keys, lowest-index priority, two-frame debounce")
    print("PASS: C4..D6 note map and phase-step table")
    print("PASS: note-change restart, attack/release envelope")
    print("PASS: behavioral simulation complete")


if __name__ == "__main__":
    main()
