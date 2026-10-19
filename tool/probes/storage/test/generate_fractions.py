"""Independent exact oracle; Python standard library only."""
from fractions import Fraction
from pathlib import Path
import json
cases = [('0.1', 1, 3), ('0.000001', 1, 7), ('12.345678', 250, 1),
         ('9000000000', 9000000000, 7), ('0.333333', 3, 1)]
fixtures = []
for entered, numerator, denominator in cases:
    expected = Fraction(entered) * Fraction(numerator, denominator)
    fixtures.append(dict(entered=entered, concentrationNumerator=numerator,
                         concentrationDenominator=denominator,
                         expected=f'{expected.numerator}/{expected.denominator}'))
Path(__file__).with_name('fractions.json').write_text(json.dumps(fixtures, indent=2) + '\n')
