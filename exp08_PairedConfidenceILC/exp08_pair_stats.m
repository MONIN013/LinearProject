function stats = exp08_pair_stats(d1, d2, binIndex)
%EXP08_PAIR_STATS Estimate repeatability from two updates at identical FF.
d1 = d1(:);
d2 = d2(:);
assert(numel(d1)==numel(d2) && all(isfinite([d1;d2])), ...
    'NikonMotor:InvalidPairedUpdate','Paired updates must be finite and equally sized.');
h = (d1-d2)/2;
signalRaw = dot(d1,d2);
signal = max(signalRaw,0);
noise = dot(h,h);
if signal+noise==0
    gate = 0;
else
    gate = signal/(signal+noise);
end
stats = struct('rawCrossEnergy',signalRaw,'signalEnergy',signal, ...
    'noiseEnergy',noise,'gate',gate,'binGate',[], ...
    'binSignalEnergy',[],'binNoiseEnergy',[]);
if nargin<3 || isempty(binIndex), return; end
binIndex = binIndex(:);
assert(numel(binIndex)==numel(d1) && all(isfinite(binIndex)) && ...
    all(binIndex==fix(binIndex)) && all(binIndex>=0), ...
    'NikonMotor:InvalidPositionBins','Position-bin indices must be nonnegative integers.');
keep = binIndex>0;
if ~any(keep), return; end
count = max(binIndex);
binSignal = max(accumarray(binIndex(keep),d1(keep).*d2(keep), ...
    [count,1],@sum,0),0);
binNoise = accumarray(binIndex(keep),h(keep).^2,[count,1],@sum,0);
binGate = zeros(count,1);
use = binSignal+binNoise>0;
binGate(use) = binSignal(use)./(binSignal(use)+binNoise(use));
stats.binGate = binGate;
stats.binSignalEnergy = binSignal;
stats.binNoiseEnergy = binNoise;
end
