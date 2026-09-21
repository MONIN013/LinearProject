function stats = exp08_pair_stats(d1, d2, binIndex)
%EXP08_PAIR_STATS Reproducibility of two update candidates at IDENTICAL FF.
% No probability interpretation. Unbiased energy identities require zero-mean,
% cross-trial-uncorrelated noise before positive-part clipping and division.
d1 = d1(:); d2 = d2(:);
h = (d1-d2)/2;
Sraw = dot(d1,d2);
V = dot(h,h);
S = max(Sraw,0);
if S+V == 0, gate = 0; else, gate = S/(S+V); end
stats = struct('rawCrossEnergy',Sraw,'signalEnergy',S,'noiseEnergy',V, ...
    'gate',gate,'binGate',[],'binSignalEnergy',[],'binNoiseEnergy',[]);
% Reference-position/direction bins are diagnostic ONLY; gate is a scalar.
if nargin < 3 || isempty(binIndex), return; end
binIndex = binIndex(:);
keep = binIndex > 0;
if ~any(keep), return; end
count = max(binIndex);
Sb = max(accumarray(binIndex(keep),d1(keep).*d2(keep),[count,1],@sum,0),0);
Vb = accumarray(binIndex(keep),h(keep).^2,[count,1],@sum,0);
bg = zeros(count,1); use = Sb+Vb > 0;
bg(use) = Sb(use)./(Sb(use)+Vb(use));
stats.binGate = bg;
stats.binSignalEnergy = Sb;
stats.binNoiseEnergy = Vb;
end
