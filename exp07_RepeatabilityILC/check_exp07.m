function check_exp07()
%CHECK_EXP07 One focused algebra smoke check. No plant, Simulink, or hardware.
% Run once after modifying exp07_update. Does not replace an exp04 hardware run.
N = 128;
target = sin((1:N)'/13);
ops.L = @(x) 2*x;
ops.B = @(x) x;
ops.Q = @(x) 0.8*x;
opt = struct('window', 5, 'minGain', 0.1, 'mode', "transport_rcs");
f = zeros(N,1); reference = f; state = struct();
for k = 1:15
    alpha = max(0.9^k, 0.3);
    e = 0.5*(target-f);
    baseline = ops.Q(f+alpha*ops.L(e));
    reference = ops.Q(reference+alpha*(target-reference));
    [f, state, info] = exp07_update(f,e,k,baseline,state,ops,opt);
    assert(norm(f-reference, Inf) < 1e-11, 'Noiseless baseline mismatch.');
    assert(abs(info.gate-1) < 1e-10, 'False gate in exact noiseless case.');
end
opt.mode = "hold";
[next, ~, info] = exp07_update(f,ones(N,1),16,2*f,struct(),ops,opt);
assert(isequal(next,f) && info.gate == 0, 'Replay changed the frozen FF.');
X = [0.3,1,1; -0.3,1,-1];
assert(rank(X) == 2 && norm(X*[1;0;-0.3]) < 1e-14);
fprintf('Exp07 algebra smoke check passed. No hardware was accessed.\n');
end
