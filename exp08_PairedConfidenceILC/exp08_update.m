function [next,state,info] = exp08_update(f,e,j,baseline,state,ops,opt)
%EXP08_UPDATE Form confidence-weighted updates from identical-FF pairs.
f = f(:);
e = e(:);
baseline = baseline(:);
assert(numel(e)==numel(f) && numel(baseline)==numel(f) && ...
    all(isfinite([f;e;baseline])), ...
    'NikonMotor:InvalidPairedUpdate','ILC callback inputs must be finite and equally sized.');
mode = string(opt.mode);
info = struct('mode',mode,'acquisition',j,'updateFormed',false, ...
    'gate',NaN,'alphaUsed',NaN,'pairNumber',NaN,'pairStats',struct(), ...
    'nextFF',[]);
if mode=="hold"
    next = f;
    return
elseif mode=="standard"
    next = baseline;
    info.gate = 1;
    info.alphaUsed = max(0.9^j,0.3);
    info.updateFormed = true;
elseif mode=="raw_rcs"
    rawOpt = struct('mode',"raw_rcs",'window',opt.rawWindow,'minGain',0.1);
    [next,state,rawInfo] = exp07_update(f,e,j,baseline,state,ops,rawOpt);
    info.gate = rawInfo.gate;
    info.alphaUsed = max(0.9^j,0.3);
    info.updateFormed = true;
elseif mode=="pair_mean" || mode=="pair_confidence"
    info.pairNumber = ceil(j/2);
    info.alphaUsed = max(0.9^(2*ceil(j/2)),0.3);
    if mod(j,2)==1
        state.firstFF = f;
        state.firstCorrection = ops.L(e);
        next = f;
    else
        assert(isfield(state,'firstFF') && isequal(f,state.firstFF), ...
            'NikonMotor:PairedFFMismatch', ...
            'Both acquisitions in a pair must use identical feedforward.');
        d1 = ops.Q(f+info.alphaUsed*state.firstCorrection)-f;
        d2 = baseline-f;
        stats = exp08_pair_stats(d1,d2,opt.binIndex);
        gate = 1;
        if mode=="pair_confidence", gate = stats.gate; end
        next = f+gate*(d1+d2)/2;
        info.gate = gate;
        info.pairStats = stats;
        info.updateFormed = true;
        state = struct();
    end
else
    error('NikonMotor:PairedILCMode','Unknown paired ILC mode: %s.',mode);
end
assert(numel(next)==numel(f) && all(isfinite(next)), ...
    'NikonMotor:InvalidPairedUpdate','Paired ILC produced an invalid waveform.');
% The last candidate is deliberately not relabelled as an applied history.f.
if j==opt.acquisitionBudget, info.nextFF = next; end
end
