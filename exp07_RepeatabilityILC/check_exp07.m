function check_exp07()
%CHECK_EXP07 実Qフィルタで無雑音時の標準更新一致と固定FFを確認する。
Ts = 1/4000;
[z, p, gain] = butter(4, 420/(1/(2*Ts)));
[sos, scale] = zp2sos(z, p, gain);
N = 1200;
target = sin((1:N)'/13) + 0.2*cos((1:N)'/57);
ops.L = @(x) 2*x;
ops.B = @(x) x;
ops.Q = @(x) exp07_q(x, sos, scale, Ts);
opt = struct('window', 5, 'minGain', 0.1, 'mode', "transport_rcs");
f = zeros(N, 1); reference = f; state = struct();
for k = 1:15
    alpha = max(0.9^k, 0.3);
    e = 0.5*(target-f);
    baseline = ops.Q(f+alpha*ops.L(e));
    reference = ops.Q(reference+alpha*(target-reference));
    [f, state, info] = exp07_update(f, e, k, baseline, state, ops, opt);
    assert(norm(f-reference, Inf) < 1e-11, 'Noiseless baseline mismatch with the actual Q filter.');
    assert(abs(info.gate-1) < 1e-10, 'False gate in the exact noiseless case.');
end
opt.mode = "hold";
[next, ~, info] = exp07_update(f, ones(N, 1), 16, 2*f, struct(), ops, opt);
assert(isequal(next, f) && info.gate == 0, 'Replay changed the frozen FF.');
fprintf('Exp07 update check passed. No hardware was accessed.\n');
end
