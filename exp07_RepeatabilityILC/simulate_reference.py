"""Synthetic finite-frequency ILC experiment; not MATLAB or hardware validation.

Run: python exp07_RepeatabilityILC/simulate_reference.py --output DIR
Requires NumPy, SciPy and matplotlib. All methods receive POSITION error only.
The circular frequency model is deliberately distinct from exp04's finite-record
stable inverse/end-padding. This script checks the proposal, not driver timing.
"""
from __future__ import annotations
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

MODES = ("standard", "raw_rcs", "transport_mean", "transport_rcs")
CASES = ("clean", "independent_noise", "model_mismatch", "drift", "correlated_noise")


def update(f, e, k, samples, mode, L, B, Q, window=5, min_gain=0.1):
    """Equation-equivalent reference for exp07_update.m; operator maps differ."""
    alpha = max(0.9**k, 0.3)
    baseline = Q(f + alpha * L(e))
    if mode == "standard":
        return baseline, samples, 1.0
    if mode == "raw_rcs":
        sample = baseline - f
    else:
        sample = Q(L(e) + B(f))
    samples = (samples + [sample])[-window:]
    matrix = np.column_stack(samples)
    count = matrix.shape[1]
    variance = 0.0 if count < 2 else np.var(matrix, axis=1, ddof=1).sum() / count
    if mode == "raw_rcs":
        step = matrix.mean(axis=1)
        candidate = baseline
    else:
        candidate = Q(f - alpha * B(f)) + alpha * matrix.mean(axis=1)
        step = candidate - f
        variance *= alpha**2
    gate = 1.0
    energy = step @ step
    if mode != "transport_mean" and count > 1 and energy + variance > 0:
        gate = max(min_gain, energy / (energy + variance))
    return f + gate * (candidate - f), samples, gate


def rms(x):
    return float(np.sqrt(np.mean(np.asarray(x) ** 2)))


def main(output: Path, seeds: int = 32):
    output.mkdir(parents=True, exist_ok=True)
    # Predeclared illustrative settings. No parameters estimated from the repo.
    settings = dict(fs_hz=4000, samples=4096, trials=15, replays=5, seeds=seeds,
                    window=5, min_gain=0.1, mass_kg=0.6, damping_Ns_m=3.0,
                    force_N_A=20.0, kp_A_m=2000.0, kv_As_m=14.0,
                    nominal_delay_samples=2, q_cutoff_hz=420,
                    noise_bandwidth_hz=180, correlation_rho=0.8, drift_peak_A=0.04,
                    noise_rms_m=2e-6, seed_start=701)
    n, fs = settings['samples'], settings['fs_hz']
    t = np.arange(n) / fs
    freq = np.fft.rfftfreq(n, 1/fs)
    s = 2j*np.pi*freq
    def frequency_J(mass, delay):
        # PD-stabilized mass/damper with an appended output delay, illustrative.
        h = 20/(mass*s*s + (3+20*14)*s + 20*2000) * np.exp(-s*delay/fs)
        h[-1] = h[-1].real  # Real self-conjugate Nyquist bin for real circulant maps.
        return h
    j_nom = frequency_J(0.6, 2)
    # Regularization caps high-frequency noise amplification; not exact exp04 L.
    ell = j_nom.conj()/(abs(j_nom)**2 + (abs(j_nom[0])*1e-4)**2)
    sos = signal.butter(4, 420, fs=fs, output='sos')
    _, response = signal.sosfreqz(sos, worN=freq, fs=fs)
    qq = abs(response)**2
    def op(H):
        return lambda x: np.fft.irfft(H*np.fft.rfft(x), n=n)
    L, B, Q = op(ell), op(ell*j_nom), op(qq)
    x = 0.1*(1-np.cos(2*np.pi*t/(n/fs)))
    v = 0.1*2*np.pi/(n/fs)*np.sin(2*np.pi*t/(n/fs))
    target = (0.04*np.sin(2*np.pi*x/0.02) +
              (0.05+0.02*np.cos(2*np.pi*x/0.12))*v +
              0.03*np.tanh(v/0.015))
    drift_shape = 0.04*np.sin(2*np.pi*t/(n/fs))
    noise_shape = np.exp(-(freq/180)**4)
    rows, learning, gates, replay_mean = [], {}, {}, {}
    deterministic_max_difference = 0.0
    max_reconstruction_difference = 0.0
    contraction = {}
    for case in CASES:
        jt = frequency_J(0.75, 3) if case == 'model_mismatch' else j_nom
        J = op(jt)
        contraction[case] = {str(a): float(np.max(abs(qq*(1-a*ell*jt))))
                             for a in (0.3, 0.9)}
        all_paths = {m: [] for m in MODES}
        all_gates = {m: [] for m in MODES}
        for seed in range(settings['seed_start'], settings['seed_start']+seeds):
            rng = np.random.default_rng(seed)
            noise = []
            previous = np.zeros(n)  # AR case starts at zero; replay continues the same process.
            for _ in range(settings['trials']+settings['replays']):
                innovation = np.fft.irfft(noise_shape*np.fft.rfft(rng.normal(size=n)), n=n)
                # Fixed distribution scaling, rather than per-trial RMS normalization.
                innovation *= settings['noise_rms_m']/np.sqrt(np.mean(
                    np.r_[noise_shape[0]**2, np.repeat(noise_shape[1:-1]**2, 2), noise_shape[-1]**2]))
                if case == 'clean':
                    innovation *= 0
                if case == 'correlated_noise':
                    previous = 0.8*previous + np.sqrt(1-0.8**2)*innovation
                    innovation = previous.copy()
                noise.append(innovation)
            last_f = {}
            for mode in MODES:
                f, samples = np.zeros(n), []
                curve, gains = [], []
                z0 = None
                for k in range(1, settings['trials']+1):
                    extra = ((k-1)/(settings['trials']-1))*drift_shape if case == 'drift' else 0
                    b = J(target+extra)
                    error = b-J(f)+noise[k-1]
                    applied = f.copy()
                    curve.append(rms(error))
                    if case == 'clean':
                        z = L(error)+B(f)
                        if z0 is None: z0 = z.copy()
                        max_reconstruction_difference = max(max_reconstruction_difference, float(max(abs(z-z0))))
                    f, samples, gain = update(f,error,k,samples,mode,L,B,Q,
                                             settings['window'],settings['min_gain'])
                    gains.append(gain)
                # Exactly like MATLAB: freeze the last APPLIED FF, not iteration 16.
                last_f[mode] = applied
                b_test = J(target + (drift_shape if case == 'drift' else 0))
                true_error = b_test-J(applied)
                replays = np.column_stack([true_error+z for z in noise[settings['trials']:]])
                rows.append(dict(case=case, mode=mode, seed=seed,
                    last_train_rms_um=curve[-1]*1e6,
                    frozen_repeatable_rms_um=rms(true_error)*1e6,
                    frozen_measured_rms_um=float(np.mean(np.sqrt(np.mean(replays**2, axis=0))))*1e6,
                    ff_rms_A=rms(applied), average_gain=float(np.mean(gains)),
                    learning_rms_mean_um=float(np.mean(curve))*1e6))
                all_paths[mode].append(curve)
                all_gates[mode].append(gains)
            if case == 'clean':
                for mode in ('transport_mean', 'transport_rcs'):
                    deterministic_max_difference = max(deterministic_max_difference,
                        float(np.max(abs(last_f[mode]-last_f['standard']))))
        learning[case] = {m: np.mean(all_paths[m], axis=0) for m in MODES}
        gates[case] = {m: np.mean(all_gates[m], axis=0) for m in MODES}
    # One direct algebra check: whole-step relaxation preserves a non-unity-Q fixed point.
    alpha, g, q = 0.3, 0.2, 0.8
    fixed = q*alpha/(1-q*(1-alpha))
    relaxed = fixed + g*(q*(fixed+alpha*(1-fixed))-fixed)
    inside_q = q*(fixed+alpha*g*(1-fixed))
    # Single symmetric roundtrip cannot distinguish v and sign(v) coefficients locally.
    design = np.array([[0.3, 1, 1], [-0.3, 1, -1]])
    null = np.array([1, 0, -0.3])
    checks = dict(clean_vs_standard_max_A=deterministic_max_difference,
                  reconstruction_max_variation_A=max_reconstruction_difference,
                  whole_step_fixed_point_error=abs(relaxed-fixed),
                  inside_Q_fixed_point_error=abs(inside_q-fixed),
                  local_design_rank=int(np.linalg.matrix_rank(design)),
                  local_null_residual=float(np.linalg.norm(design@null)),
                  contraction_screen=contraction)
    assert deterministic_max_difference < 1e-10
    assert max_reconstruction_difference < 1e-10
    assert abs(relaxed-fixed) < 1e-14
    assert np.linalg.matrix_rank(design) == 2
    summary=[]
    for case in CASES:
        ref = np.array([r['frozen_repeatable_rms_um'] for r in rows if r['case']==case and r['mode']=='standard'])
        for mode in MODES:
            group=[r for r in rows if r['case']==case and r['mode']==mode]
            values=np.array([r['frozen_repeatable_rms_um'] for r in group])
            diff=values-ref
            half=1.96*np.std(diff, ddof=1)/np.sqrt(seeds)
            summary.append(dict(case=case,mode=mode,
                repeatable_mean_um=float(values.mean()),
                measured_mean_um=float(np.mean([r['frozen_measured_rms_um'] for r in group])),
                paired_delta_um=float(diff.mean()),paired_delta_ci95_low_um=float(diff.mean()-half),
                paired_delta_ci95_high_um=float(diff.mean()+half),
                average_gain=float(np.mean([r['average_gain'] for r in group]))))
    for name, data in [('trials.csv',rows), ('summary.csv',summary)]:
        with (output/name).open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=data[0].keys());writer.writeheader();writer.writerows(data)
    (output/'settings.json').write_text(json.dumps(settings,indent=2)+'\n')
    (output/'checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    for kind, case, curves, ylabel, filename in [
        ('gain','clean',gates['clean'],'Scalar learning gate','clean_gate'),
        ('error','independent_noise',learning['independent_noise'],'Measured position RMS [um]','noisy_learning')]:
        fig,ax=plt.subplots(figsize=(7.0,4.2))
        for mode in MODES:
            ax.plot(np.arange(1,settings['trials']+1),curves[mode]*(1e6 if kind=='error' else 1),label=mode)
        ax.set_xlabel('Applied trial');ax.set_ylabel(ylabel)
        ax.set_title('Synthetic experiment: '+case.replace('_',' '));ax.grid(True);ax.legend(fontsize=8)
        fig.tight_layout();fig.savefig(output/(filename+'.svg'));fig.savefig(output/(filename+'.png'),dpi=180);plt.close(fig)
    print(json.dumps(checks,indent=2))
    for row in summary: print(row)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('docs/exp07/synthetic'))
    args=parser.parse_args()
    main(args.output)
