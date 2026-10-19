"""Independent expected values from Python's standard-library Fraction.
Run from repository root; fixture is intentional checked-in test evidence.
"""
from fractions import Fraction
import json
from pathlib import Path
cases = []
for amount, concentration in [('1', '3'), ('0.000001', '0.000003'), ('9000000000', '0.000001'), ('1.234567', '7.125'), ('0002.500000', '3')]:
    mass, strength = Fraction(amount), Fraction(concentration)
    volume = mass / strength
    cases.append(dict(entered=amount, strength=concentration, mass=str(mass.numerator)+'/'+str(mass.denominator), volume=str(volume.numerator)+'/'+str(volume.denominator), repeated=str((volume*999).numerator)+'/'+str((volume*999).denominator)))
Path('test/stock/exact_oracle.json').write_text(json.dumps(cases, indent=2)+'\n')

# Independent SQL aggregate boundary: TEXT retrieval plus Fraction avoids both
# signed-int64 SUM overflow and REAL's loss of the final unit.
import sqlite3
connection = sqlite3.connect(':memory:')
connection.execute('CREATE TABLE movements (sequence INTEGER PRIMARY KEY, numerator TEXT NOT NULL, denominator TEXT NOT NULL)')
connection.executemany('INSERT INTO movements VALUES (?, ?, ?)', [(i, '9000000000000000', '1000000') for i in range(1100)])
exact = sum((Fraction(int(n), int(d)) for n, d in connection.execute('SELECT numerator, denominator FROM movements ORDER BY sequence')), Fraction())
assert exact == Fraction(9900000000000)
try:
    connection.execute('SELECT SUM(CAST(numerator AS INTEGER)) FROM movements').fetchone()
except sqlite3.OperationalError as error:
    assert 'overflow' in str(error)
else:
    raise AssertionError('Expected SQLite integer aggregate overflow')
connection.close()
print('Python Fraction fixtures and SQLite int64 overflow boundary verified')
