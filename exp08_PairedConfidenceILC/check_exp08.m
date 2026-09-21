function check_exp08()
%CHECK_EXP08 Focused finite-record algebra check; no model or hardware access.
Ts = 0.001;
[z,p,k] = butter(4,100/(1/(2*Ts)));
[sos,scale] = zp2sos(z,p,k);
ops = struct('L',@(e)2*e,'Q',@(f)exp07_q(f,sos,scale,Ts));
f = zeros(256,1);
e1 = sin((1:256)'/17);
e2 = e1+0.05*cos((1:256)'/11);
opt = struct('mode',"pair_mean",'binIndex',repelem((1:4)',64), ...
    'rawWindow',5,'acquisitionBudget',2);
b1 = ops.Q(f+0.81*ops.L(e1));
[held,state,first] = exp08_update(f,e1,1,b1,struct(),ops,opt);
b2 = ops.Q(f+0.81*ops.L(e2));
[next,~,second] = exp08_update(held,e2,2,b2,state,ops,opt);
expected = ops.Q(f+0.81*ops.L((e1+e2)/2));
assert(isequal(held,f) && ~first.updateFormed && ...
    norm(next-expected,Inf)<1e-11 && isequal(second.nextFF,next));
same = exp08_pair_stats(e1,e1,opt.binIndex);
opposite = exp08_pair_stats(e1,-e1,opt.binIndex);
zero = exp08_pair_stats(zeros(size(e1)),zeros(size(e1)),opt.binIndex);
assert(same.gate==1 && opposite.gate==0 && zero.gate==0 && ...
    all(isfinite(zero.binGate)));
fprintf('Exp08 finite-record algebra check passed. No hardware was accessed.\n');
end
