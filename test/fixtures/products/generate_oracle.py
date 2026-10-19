"""Independent Fraction oracle for ticket 13; not an application test.

Run from any working directory. This retained generator and JSON are intended
source evidence, independent of the Dart exact-amount implementation.
"""
from fractions import Fraction
from pathlib import Path
import json


def pair(value):
    if value is None:
        return None
    return f'{value.numerator}/{value.denominator}'


cases = []
for name, volume, concentrations, repeats in [
    ('two-known', '0.500000', ['3', '7'], 1),
    ('one-unknown', '0.125000', ['2.5', None, '0.000001'], 1),
    ('all-unknown', '1.25', [None, None], 1),
    ('repeating-internal-volume', '1/3', ['3', '7', None], 999),
    ('minimum-volume', '0.000001', ['0.000001', '9000000000'], 1001),
    ('large-derived-mass', '9000000000', ['9000000000', '0.000001'], 3),
]:
    v = Fraction(volume)
    masses = [None if c is None else v * Fraction(c) for c in concentrations]
    cases.append(dict(
        id=name, volume=pair(v), labelled_concentrations=concentrations,
        component_masses=[pair(m) for m in masses], repeats=repeats,
        total_physical_volume=pair(v * repeats),
        total_component_masses=[pair(None if m is None else m * repeats) for m in masses],
        physical_outflows_per_administration=1,
    ))

# Current-revision reporting differs from physical supply. Correcting the first
# of three records to 2/3 ml retains its already-consumed 1/3 ml when chosen.
volumes = [Fraction(1, 3)] * 3
original = sum(volumes)
volumes[0] = Fraction(2, 3)
corrected = sum(volumes)
correction = dict(
    original_total_volume=pair(original), corrected_report_volume=pair(corrected),
    retained_physical_use=pair(original),
    original_component_totals=[pair(original * c) for c in (3, 7)],
    corrected_component_totals=[pair(corrected * c) for c in (3, 7)],
    after_void_third_report_volume=pair(corrected - Fraction(1, 3)),
    after_void_retained_physical_use=pair(original),
)
assert cases[3]['total_physical_volume'] == '333/1'
assert cases[3]['total_component_masses'] == ['999/1', '2331/1', None]
assert correction['corrected_component_totals'] == ['4/1', '28/3']
assert Fraction(cases[-1]['component_masses'][0]) > 2**63 - 1
result = dict(cases=cases, correction=correction)
Path(__file__).with_name('exact_oracle.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS six independent product arithmetic cases and current-revision correction oracle')
