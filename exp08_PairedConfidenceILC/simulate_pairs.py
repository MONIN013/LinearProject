"""Exp08 synthetic comparison at equal PHYSICAL acquisition cost.

python exp08_PairedConfidenceILC/simulate_pairs.py --output docs/exp08/synthetic
NumPy/SciPy only. Not the finite-record MATLAB inverse or a hardware simulation.
All methods use measured POSITION error. No true-error signal enters the update.
"""
from __future__ import annotations
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from scipy import signal

MODES = ('standard', 'raw_rcs', 'pair_mean', 'pair_confidence')
CASES = ('clean', 'independent_noise', 'model_mismatch', 'drift', 'correlated_noise')


def pair_statistics(d1, d2):
    """Same scalar estimator as exp08_pair_stats.m (no positive gate floor)."""
    h = (d1-d2)/2
    cross = float(d1 @ d2)
    variance = float(h @ h)
    energy = max(cross, 0.0)
    gate = energy/(energy+variance) if energy+variance > 0 else 0.0
    return gate, energy, variance


def step(f, e, j, state, mode, L, Q):
    """j is 1-based physical acquisition number; two candidates share alpha."""
    alpha = max(0.9**j, 0.3)
    baseline = Q(f+alpha*L(e))
    if mode == 'standard':
        return baseline, state, 1.0
    if mode == 'raw_rcs':
        state['samples'] = (state.get('samples', []) + [baseline-f])[-5:]
        matrix = np.column_stack(state['samples'])
        n = matrix.shape[1]
        variance = 0.0 if n < 2 else np.var(matrix, axis=1, ddof=1).sum()/n
        mean_step = matrix.mean(axis=1)
        energy = float(mean_step @ mean_step)
        gate = max(0.1, energy/(energy+variance)) if energy+variance > 0 else 1.0
        return f+gate*(baseline-f), state, gate
    if j % 2:
        state = dict(first_ff=f.copy(), first_correction=L(e))
        return f.copy(), state, np.nan
    assert np.array_equal(f, state['first_ff'])
    d1 = Q(f+alpha*state['first_correction'])-f
    d2 = baseline-f
    gate = 1.0 if mode == 'pair_mean' else pair_statistics(d1, d2)[0]
    return f+gate*(d1+d2)/2, {}, gate


def algebra_check():
    """One focused reference check; MATLAB execution is separately required."""
    L, Q = lambda x: 2*x, lambda x: 0.8*x
    f = np.zeros(4); e1 = np.array([1., -2., 3., -4.]); e2 = e1+0.2
    held, state, gate = step(f,e1,1,{},'pair_mean',L,Q)
    assert np.array_equal(held,f) and np.isnan(gate)
    got, _, _ = step(held,e2,2,state,'pair_mean',L,Q)
    expected = Q(f+0.81*L((e1+e2)/2))
    assert np.max(abs(got-expected)) < 1e-12
    assert pair_statistics(e1,e1)[0] == 1.0
    assert pair_statistics(e1,-e1)[0] == 0.0
    assert pair_statistics(f,f)[0] == 0.0
    return dict(pair_hold_exact=True, common_alpha_mean_max_error=float(max(abs(got-expected))),
                identical_gate=1.0, opposite_gate=0.0, zero_gate=0.0)


def main(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    cfg = dict(fs_hz=4000, samples=4096, train_acquisitions=30, replay_acquisitions=5,
               seeds=32, seed_start=801, mass_kg=0.6, damping_Ns_m=3.0, force_N_A=20.0,
               kp_A_m=2000.0, kv_As_m=14.0, nominal_delay_samples=2, q_cutoff_hz=420,
               noise_rms_m=2e-6, noise_bandwidth_hz=180, correlation_rho=0.8,
               drift_peak_A=0.04, regularization=1e-4,
               alpha_clock='physical acquisition; common pair-closing alpha',
               final_ff='candidate after acquisition 30, first applied at replay 1')
    checks = algebra_check()
    n, fs, budget, replays = (cfg[k] for k in ('samples','fs_hz','train_acquisitions','replay_acquisitions'))
    freq = np.fft.rfftfreq(n,1/fs); s = 2j*np.pi*freq
    def frequency_J(mass, delay):
        H = 20/(mass*s*s+(3+20*14)*s+20*2000)*np.exp(-s*delay/fs)
        H[-1] = H[-1].real
        return H
    nominal = frequency_J(0.6,2)
    ell = nominal.conj()/(abs(nominal)**2+(abs(nominal[0])*cfg['regularization'])**2)
    sos = signal.butter(4,420,fs=fs,output='sos')
    _, response = signal.sosfreqz(sos,worN=freq,fs=fs)
    qq = abs(response)**2
    def op(H):
        return lambda x: np.fft.irfft(H*np.fft.rfft(x),n=n)
    L,Q = op(ell),op(qq)
    t = np.arange(n)/fs
    x = 0.1*(1-np.cos(2*np.pi*t/(n/fs)))
    v = 0.1*2*np.pi/(n/fs)*np.sin(2*np.pi*t/(n/fs))
    target = 0.04*np.sin(2*np.pi*x/0.02)+(0.05+0.02*np.cos(2*np.pi*x/0.12))*v+0.03*np.tanh(v/0.015)
    drift = 0.04*np.sin(2*np.pi*t/(n/fs))
    shape = np.exp(-(freq/180)**4)
    white_to_shaped_rms = np.sqrt((shape[0]**2+2*np.sum(shape[1:-1]**2)+shape[-1]**2)/n)
    rows, curve_rows = [], []
    clean_pair_max_difference = 0.0
    checks['contraction_screen'] = {}
    for case in CASES:
        true_H = frequency_J(0.75,3) if case == 'model_mismatch' else nominal
        J = op(true_H)
        checks['contraction_screen'][case] = {str(a):float(np.max(abs(qq*(1-a*ell*true_H)))) for a in (0.3,0.9)}
        for seed in range(cfg['seed_start'],cfg['seed_start']+cfg['seeds']):
            rng = np.random.default_rng(seed)
            noise = []
            previous = np.zeros(n)
            for _ in range(budget+replays):
                innovation = np.fft.irfft(shape*np.fft.rfft(rng.normal(size=n)),n=n)
                innovation *= cfg['noise_rms_m']/white_to_shaped_rms
                if case == 'clean': innovation *= 0
                if case == 'correlated_noise':
                    previous = 0.8*previous+np.sqrt(1-0.8**2)*innovation
                    innovation = previous.copy()
                noise.append(innovation)
            final_by_mode = {}
            for mode in MODES:
                f, state, gains, curve = np.zeros(n), {}, [], []
                for j in range(1,budget+1):
                    extra = drift*(j-1)/(budget-1) if case == 'drift' else 0
                    error = J(target+extra-f)+noise[j-1]
                    observed = float(np.sqrt(np.mean(error**2))*1e6)
                    f,state,gate = step(f,error,j,state,mode,L,Q)
                    curve.append(observed); gains.append(gate)
                    curve_rows.append(dict(case=case,mode=mode,seed=seed,acquisition=j,
                                           observed_rms_um=observed,gate=gate))
                assert mode in ('standard','raw_rcs') or not state
                # Use ALL 30 acquired errors. This FF has never been applied before replay.
                final_by_mode[mode] = f.copy()
                final_target = target+(drift if case == 'drift' else 0)
                repeatable = J(final_target-f)
                observations = np.column_stack([repeatable+z for z in noise[budget:]])
                row = dict(case=case,mode=mode,seed=seed,train_acquisitions=budget,
                    update_decisions=budget if mode in ('standard','raw_rcs') else budget//2,
                    replay_acquisitions=replays,
                    repeatable_rms_um=float(np.sqrt(np.mean(repeatable**2))*1e6),
                    observed_rms_um=float(np.mean(np.sqrt(np.mean(observations**2,axis=0)))*1e6),
                    training_mean_rms_um=float(np.mean(curve)),
                    mean_gate=float(np.nanmean(gains)),ff_rms_A=float(np.sqrt(np.mean(f**2))))
                rows.append(row)
            if case == 'clean':
                clean_pair_max_difference = max(clean_pair_max_difference,
                    float(np.max(abs(final_by_mode['pair_mean']-final_by_mode['pair_confidence']))))
    checks['clean_pair_mean_vs_confidence_max_A'] = clean_pair_max_difference
    assert clean_pair_max_difference < 1e-10
    summary = []
    for case in CASES:
        refs = {mode:np.array([r['repeatable_rms_um'] for r in rows if r['case']==case and r['mode']==mode]) for mode in MODES}
        for mode in MODES:
            group = [r for r in rows if r['case']==case and r['mode']==mode]
            diff = refs[mode]-refs['pair_mean']
            half = 1.96*np.std(diff,ddof=1)/np.sqrt(cfg['seeds'])
            summary.append(dict(case=case,mode=mode,
                repeatable_mean_um=float(refs[mode].mean()),
                observed_mean_um=float(np.mean([r['observed_rms_um'] for r in group])),
                delta_vs_pair_mean_um=float(diff.mean()),
                delta_ci95_low_um=float(diff.mean()-half),delta_ci95_high_um=float(diff.mean()+half),
                mean_gate=float(np.mean([r['mean_gate'] for r in group]))))
    for name,data in [('seeds.csv',rows),('learning.csv',curve_rows),('summary.csv',summary)]:
        with (output/name).open('w',newline='') as handle:
            writer = csv.DictWriter(handle,fieldnames=data[0].keys());writer.writeheader();writer.writerows(data)
    (output/'settings.json').write_text(json.dumps(cfg,indent=2)+'\n')
    (output/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    print('case,mode,repeatable_mean_um,observed_mean_um,mean_gate')
    for r in summary:
        print(f"{r['case']},{r['mode']},{r['repeatable_mean_um']:.6f},{r['observed_mean_um']:.6f},{r['mean_gate']:.6f}")
    print(json.dumps(checks,indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('docs/exp08/synthetic'))
    args = parser.parse_args()
    main(args.output)
