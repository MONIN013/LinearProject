function [next, state, info] = exp07_update(f, e, k, baseline, state, ops, opt)
%EXP07_UPDATE Offline, trial-to-trial FF update from POSITION error only.
% ops.L: existing Le; ops.B: L*Jhat; ops.Q: existing forward/backward filter
% including the 25 ms endpoint operation. All maps use the same record length.
% baseline is the EXACT candidate computed by exp04, including alpha and Q.
% opt.mode: standard | raw_rcs | transport_mean | transport_rcs | hold.
f = f(:); e = e(:); baseline = baseline(:);
alpha = max(0.9^k, 0.3);
info = struct('gate', 1, 'windowCount', 1, 'meanNoiseEnergy', 0, ...
    'baselineStepNorm', norm(baseline-f), 'candidateStepNorm', 0);
mode = string(opt.mode);
if mode == "hold"
    next = f;
    info.gate = 0;
    return
elseif mode == "standard"
    next = baseline;
    info.candidateStepNorm = norm(next-f);
    return
end

if ~isfield(state, 'samples'), state.samples = zeros(numel(f), 0); end
if mode == "raw_rcs"
    % Diagnostic ablation, NOT a reproduction of a named literature method.
    % Historical raw steps still contain learning transients and changing alpha.
    sample = baseline-f;
    state.samples = append_window(state.samples, sample, opt.window);
    n = size(state.samples, 2);
    meanStep = mean(state.samples, 2);
    noise = mean_noise_energy(state.samples);
    candidate = baseline;
elseif mode == "transport_mean" || mode == "transport_rcs"
    Bf = ops.B(f);
    z = ops.L(e) + Bf;
    % Store Qz, not Le: z = Lb + L(Jhat-J)f + Ln.
    state.samples = append_window(state.samples, ops.Q(z), opt.window);
    n = size(state.samples, 2);
    candidate = ops.Q(f-alpha*Bf) + alpha*mean(state.samples, 2);
    meanStep = candidate-f;
    noise = alpha^2*mean_noise_energy(state.samples);
else
    error('exp07:Mode', 'Unknown update mode: %s.', mode);
end

gate = 1;
if mode ~= "transport_mean" && n > 1
    energy = sum(meanStep.^2);
    if energy + noise > 0
        gate = max(opt.minGain, energy/(energy+noise));
    end
end
% Relax the WHOLE Q-filtered step. Putting gate inside Q leaks the memory
% when gate=0 and generally changes the non-unity-Q fixed point.
next = f + gate*(candidate-f);
info.gate = gate;
info.windowCount = n;
info.meanNoiseEnergy = noise;
info.candidateStepNorm = norm(candidate-f);
end

function samples = append_window(samples, sample, window)
samples(:, end+1) = sample(:);
samples = samples(:, max(1, size(samples, 2)-window+1):end);
end

function value = mean_noise_energy(samples)
n = size(samples, 2);
if n < 2
    value = 0;
else
    % Plug-in estimate for independent, stationary trial noise, not a guarantee.
    value = sum(var(samples, 0, 2))/n;
end
end
