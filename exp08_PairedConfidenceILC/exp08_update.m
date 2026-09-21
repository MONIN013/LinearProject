function [next,state,info] = exp08_update(f,e,j,baseline,state,ops,opt)
%EXP08_UPDATE Use the exp07 hook; do not change exp04 capture or protection.
% j counts PHYSICAL acquisitions, including the held first half of a pair.
% ops.L and ops.Q are the existing finite-record exp04 learning/filter maps.
% No Jhat, real-current measurement or true disturbance is used by the pair.
f = f(:); e = e(:); mode = string(opt.mode);
info = struct('mode',mode,'acquisition',j,'updateFormed',false, ...
    'gate',NaN,'alphaUsed',NaN,'pairNumber',NaN,'pairStats',struct(), ...
    'nextFF',[]);
if mode == "hold"
    next = f; % Q is not applied: exactly the same FF, not a leaky memory.
    return
elseif mode == "standard"
    next = baseline;
    info.gate = 1; info.alphaUsed = max(0.9^j,0.3);
    info.updateFormed = true;
elseif mode == "raw_rcs"
    rawOpt = struct('mode',"raw_rcs",'window',opt.rawWindow,'minGain',0.1);
    [next,state,rawInfo] = exp07_update(f,e,j,baseline,state,ops,rawOpt);
    info.gate = rawInfo.gate; info.alphaUsed = max(0.9^j,0.3);
    info.updateFormed = true;
elseif mode == "pair_mean" || mode == "pair_confidence"
    info.pairNumber = ceil(j/2);
    % Both candidates use alpha at the CLOSING acquisition, not two different
    % exp04 baseline alphas. Decay is charged to the physical-run budget.
    info.alphaUsed = max(0.9^(2*ceil(j/2)),0.3);
    if mod(j,2) == 1
        state.firstFF = f;
        state.firstCorrection = ops.L(e);
        next = f;
    else
        assert(isfield(state,'firstFF') && isequal(f,state.firstFF), ...
            'exp08:PairMismatch','The two acquisitions must use identical FF.');
        d1 = ops.Q(f+info.alphaUsed*state.firstCorrection)-f;
        d2 = baseline-f; % exp04 uses the same alpha on this even acquisition.
        stats = exp08_pair_stats(d1,d2,opt.binIndex);
        gate = 1;
        if mode == "pair_confidence", gate = stats.gate; end
        next = f + gate*(d1+d2)/2; % Relax the WHOLE Q-filtered update.
        info.gate = gate; info.pairStats = stats; info.updateFormed = true;
        state = struct();
    end
else
    error('exp08:Mode','Unknown mode: %s.',mode);
end
% Retain the final computed candidate for deployment on replay #1. It has NOT
% yet been applied: never relabel it as history.f(:,end) or measured performance.
if j == opt.acquisitionBudget, info.nextFF = next; end
end
