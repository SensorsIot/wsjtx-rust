#!/usr/bin/env python3
"""Independent complete-enumeration oracle; Python standard library only.

Normal mode recomputes and checks frozen expected.json; never writes files.
--print-inputs reproduces formula-defined inputs on stdout.
--print-expected recomputes expected results on stdout, without frozen comparison.
All scores are parsed from JSON decimal tokens directly into Decimal.
"""
from pathlib import Path
from decimal import Decimal, localcontext
import argparse
import hashlib
import itertools
import json

ROOT = Path(__file__).resolve().parent
PRECISION = 100


def encode(value):
    return json.dumps(value, indent=2, ensure_ascii=True, allow_nan=False) + '\n'


def formula_inputs():
    """Integer arithmetic chooses every score before oracle evaluation."""
    def masks(g, replacements=None):
        ans = [[True] * 4 for _ in range(2 * g)] + [[True, False, False, False]]
        for pos, tones in (replacements or {}).items():
            ans[pos] = [t in tones for t in range(4)]
        return ans

    def factors(g, kind):
        out = []
        for k in range(g):
            vals = []
            for l, t, u, r in itertools.product(range(4), repeat=4):
                if kind == 'uniform':
                    n, d = 0, 1
                elif kind == 'rational':
                    n, d = ((17*l + 11*t + 7*u + 3*r + 5*l*u - 9*t*r) % 37) - 18, 8
                elif kind == 'middle':
                    n, d = ((13*l + 5*t + 19*u + 7*r + 11*k + 3*t*u) % 43) - 21, 4
                elif kind == 'ramp':
                    n, d = 6*t - 5*u + 3*r - 2*l + 4*k*(t-u) - 3*abs(t-r), 8
                elif kind == 'coupled':
                    n, d = ((29*l + 17*t + 11*u + 7*r + 13*k + 19*l*r + 23*t*u) % 61) - 30, 8
                elif kind == 'extreme':
                    n, d = (800 if (l + 2*t + 3*u + r + k) % 5 == 0 else -800), 1
                else:
                    raise ValueError(kind)
                # Divisors 1, 4 and 8 have exact terminating decimals. Conversion
                # merely emits the chosen decimal token; no binary score arithmetic.
                vals.append(n if d == 1 else float(str(Decimal(n) / Decimal(d))))
            out.append(vals)
        return out

    cases = [
        dict(id='uniform_g1', G=1, formula='uniform', allowed=masks(1)),
        dict(id='asymmetric_rational_g1', G=1, formula='rational', allowed=masks(1)),
        dict(id='known_middle_g2', G=2, formula='middle', allowed=masks(2, {1:[2], 2:[0,3]})),
        dict(id='ramp_constraints_g2', G=2, formula='ramp', allowed=masks(2, {0:[0,1], 1:[1,2], 2:[2,3], 3:[3]})),
        dict(id='coupled_g3', G=3, formula='coupled', allowed=masks(3, {0:[0,2,3], 3:[1,3], 5:[0,1,2]})),
        dict(id='extreme_800_g3', G=3, formula='extreme', allowed=masks(3)),
    ]
    for case in cases:
        case['factors'] = factors(case['G'], case['formula'])
    for source in (cases[1], cases[5]):
        # Integers or exactly representable eighths, including the offset.
        shifted = dict(id=source['id'] + '_shifted', G=source['G'], formula=source['formula'],
                       allowed=source['allowed'], shift_of=source['id'], constant_offset=1000000)
        shifted['factors'] = [[float(str(Decimal(str(x)) + Decimal(1000000)))
                              for x in factor] for factor in source['factors']]
        cases.append(shifted)
    return {
        'schema': 'pair-chain-complete-enumeration-inputs-v1',
        'metadata': {
            'oracle_scope': 'Abstract finite factor math only; not a waveform oracle; no FT4 quality claims.',
            'precision_decimal_digits': PRECISION,
            'source': 'Deterministic formula_inputs() in standalone producer.py; frozen before candidate execution.',
            'formula_convention': 'k is zero-based factor index; l,t,u,r each run 0..3; Python nonnegative modulo.',
            'formulas': {
                'uniform': '0',
                'rational': '(((17*l+11*t+7*u+3*r+5*l*u-9*t*r)%37)-18)/8',
                'middle': '(((13*l+5*t+19*u+7*r+11*k+3*t*u)%43)-21)/4',
                'ramp': '(6*t-5*u+3*r-2*l+4*k*(t-u)-3*abs(t-r))/8',
                'coupled': '(((29*l+17*t+11*u+7*r+13*k+19*l*r+23*t*u)%61)-30)/8',
                'extreme': '800 if (l+2*t+3*u+r+k)%5 == 0 else -800',
                'shift': 'Add exactly 1000000 to every entry of every factor in shift_of.'
            },
            'index': '((l*4+t)*4+u)*4+r',
            'weight': 'sum(k=0..G-1) F[k](z[2*k-1],z[2*k],z[2*k+1],z[2*k+2]); z[-1]=z[2*G]=0',
            'prior': 'Each source variable uniform over its allowed tones, independently; constant source-prior weight cancels in normalized marginals.',
            'allowed': '2*G+1 rows for z[0] through z[2*G]; final boundary row is [true,false,false,false]. Other masks are abstract known-symbol/data constraints.',
            'expected': 'Natural log posterior per tone for every source variable plus final boundary; impossible tones are JSON null; finite values are exact decimal strings at 100-digit working precision.',
            'method': 'Enumerate all 4^(2*G) source assignments, rejecting masks. Precompute Decimal exp(score-global_factor_max); multiply complete-path factors; sum complete-path mass by variable/tone; normalize then ln. No trellis or message passing.'
        },
        'cases': cases
    }


def read_inputs():
    return json.loads((ROOT / 'inputs.json').read_text(), parse_float=Decimal)


def compute(data):
    results = []
    with localcontext() as ctx:
        ctx.prec = PRECISION
        tolerance = Decimal('1e-90')
        for case in data['cases']:
            g, allowed = case['G'], case['allowed']
            assert 1 <= g <= 3 and len(allowed) == 2*g+1
            assert allowed[-1] == [True, False, False, False]
            assert all(len(row) == 4 and all(type(b) is bool for b in row) and any(row) for row in allowed)
            assert len(case['factors']) == g
            tables = []
            for values in case['factors']:
                assert len(values) == 256
                values = [Decimal(v) for v in values]
                assert all(v.is_finite() for v in values)
                peak = max(values)
                cache = {v: (v-peak).exp() for v in set(values)}
                tables.append([cache[v] for v in values])
            mass = [[Decimal(0)]*4 for _ in allowed]
            total, valid = Decimal(0), 0
            for path in itertools.product(range(4), repeat=2*g):
                if not all(allowed[s][tone] for s, tone in enumerate(path)):
                    continue
                extended = (0,) + path + (0,)
                weight = Decimal(1)
                for k, table in enumerate(tables):
                    l,t,u,r = extended[2*k:2*k+4]
                    weight *= table[((l*4+t)*4+u)*4+r]
                total += weight
                valid += 1
                for s, tone in enumerate(path + (0,)):
                    mass[s][tone] += weight
            assert total > 0
            logmarginals = []
            for s, row in enumerate(mass):
                probs = [x/total for x in row]
                assert abs(sum(probs)-1) <= tolerance
                assert all((p > 0) == allowed[s][t] for t,p in enumerate(probs))
                if sum(allowed[s]) == 1:
                    assert probs[allowed[s].index(True)] == 1
                logmarginals.append([str(p.ln()) if p else None for p in probs])
            results.append(dict(id=case['id'], enumerated_paths=4**(2*g), valid_paths=valid,
                                log_marginals=logmarginals))
        by_id = {r['id']: r for r in results}
        for case in data['cases']:
            if 'shift_of' in case:
                # Global factor shifts cancel *before* exp, so equality is exact.
                assert by_id[case['id']]['log_marginals'] == by_id[case['shift_of']]['log_marginals']
    return {'schema': 'pair-chain-complete-enumeration-expected-v1',
            'precision_decimal_digits': PRECISION, 'cases': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--print-inputs', action='store_true')
    parser.add_argument('--print-expected', action='store_true')
    args = parser.parse_args()
    if args.print_inputs:
        print(encode(formula_inputs()), end='')
        return
    data = read_inputs()
    # Verify that frozen numeric tokens faithfully match the documented formula.
    regenerated = json.loads(encode(formula_inputs()), parse_float=Decimal)
    assert data == regenerated, 'Frozen inputs differ from fixed formulas'
    expected = compute(data)
    if args.print_expected:
        print(encode(expected), end='')
        return
    frozen = json.loads((ROOT / 'expected.json').read_text())
    assert expected == frozen, 'Frozen expected values differ from complete enumeration'
    print('PASS: 8 cases; all probabilities, masks, known constraints, and 2 constant-shift pairs verified.')
    print('Complete assignments visited:', sum(c['enumerated_paths'] for c in expected['cases']))
    print('Allowed complete assignments:', sum(c['valid_paths'] for c in expected['cases']))
    for name in ('inputs.json', 'expected.json', 'producer.py'):
        print(hashlib.sha256((ROOT/name).read_bytes()).hexdigest(), name)


if __name__ == '__main__':
    main()
