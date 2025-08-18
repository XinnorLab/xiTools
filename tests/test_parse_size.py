import runpy
from decimal import Decimal

mod = runpy.run_path('block-info')
parse_size = mod['parse_size']


def test_parse_size_large_integer():
    val = 18446744073709551615
    assert parse_size(str(val)) == val


def test_parse_size_fractional_with_suffix():
    expected = int(Decimal('1.5') * (1024 ** 4))
    assert parse_size('1.5T') == expected
