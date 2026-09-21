function check_exp08()
%CHECK_EXP08 One focused algebra/pair-state check; no Simulink or hardware.
ops = struct('L',@(e) 2*e,'Q',@(f) 0.8*f);
f = zeros(4,1); e1 = [1;-2;3;-4]; e2 = e1+[0.2;-0.1;0.3;0.1];
opt = struct('mode',"pair_mean",'binIndex',[1;1;2;2], ...
    'rawWindow',5,'acquisitionBudget',2);
b1 = ops.Q(f+0.9*ops.L(e1));
[held,state,info1] = exp08_update(f,e1,1,b1,struct(),ops,opt);
assert(isequal(held,f) && ~info1.updateFormed);
b2 = ops.Q(f+0.81*ops.L(e2));
[next,~,info2] = exp08_update(held,e2,2,b2,state,ops,opt);
expected = ops.Q(f+0.81*ops.L((e1+e2)/2));
assert(norm(next-expected,Inf)<1e-12 && isequal(info2.nextFF,next));
assert(info1.alphaUsed == info2.alphaUsed);
same = exp08_pair_stats(e1,e1,opt.binIndex);
assert(same.gate == 1 && all(same.binGate == 1));
opposite = exp08_pair_stats(e1,-e1,opt.binIndex);
assert(opposite.gate == 0);
zero = exp08_pair_stats(zeros(4,1),zeros(4,1),opt.binIndex);
assert(zero.gate == 0 && all(isfinite(zero.binGate)));
opt.mode = "pair_confidence";
[held,state] = exp08_update(f,e1,1,b1,struct(),ops,opt);
b2 = ops.Q(f+0.81*ops.L(e1));
[next,~,info] = exp08_update(held,e1,2,b2,state,ops,opt);
assert(info.gate == 1 && norm(next-b2,Inf)<1e-12);
opt.mode = "hold";
[held,~,~] = exp08_update(next,e1,3,0.8*next,struct(),ops,opt);
assert(isequal(held,next));
fprintf('Exp08 paired-update algebra check passed. No hardware accessed.\n');
end
