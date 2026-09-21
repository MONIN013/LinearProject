function [next, state, info] = exp07_update(f, e, k, baseline, state, ops, opt)
%EXP07_UPDATE 位置誤差から次試行のFFを計算する。
% baselineはexp04の学習率、Q、25 ms端処理を適用済みの候補。
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
    % 未補正の更新差には学習過渡と学習率の変化も含まれる。
    state.samples = append_window(state.samples, baseline-f, opt.window);
    n = size(state.samples, 2);
    meanStep = mean(state.samples, 2);
    noise = mean_noise_energy(state.samples);
    candidate = baseline;
elseif mode == "transport_mean" || mode == "transport_rcs"
    Bf = ops.B(f);
    z = ops.L(e) + Bf;
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
% Qの内側にgateを掛けると、gate=0でもFFが変わるため更新全体を緩和する。
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
    value = sum(var(samples, 0, 2))/n;
end
end
