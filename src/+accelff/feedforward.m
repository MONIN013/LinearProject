function [f, detail] = feedforward(model, x, v, a, baseline, gain, Ts, advance, limits)
%FEEDFORWARD Offline replacement/blending of TOTAL FF; not an extra inertia FF.
% baseline is a frozen, full-length approved FF waveform. gain in [0,1].
% Do not add Jn*a after this function: alpha*a already contains inertia.
% Refuse holes/extrapolation during motion; use baseline below velocity floor.
% Time advance applies ONCE to the composed FF, not to the reference or logs.
vectors={x,v,a,baseline};
assert(numel(x)>=2,'accelff:Length','At least two samples are required.');
for k=1:numel(vectors)
    validateattributes(vectors{k},{'double'},{'column','real','finite','numel',numel(x)});
end
validateattributes(Ts,{'double'},{'scalar','finite','positive'});
validateattributes(gain,{'double'},{'scalar','finite','>=',0,'<=',1});
validateattributes(advance,{'double'},{'scalar','integer','>=',0,'<',numel(x)});
validateattributes(limits.ff_A,{'double'},{'scalar','finite','positive'});
validateattributes(limits.ff_slew_A_s,{'double'},{'scalar','finite','positive'});
validateattributes(limits.velocity_floor,{'double'},{'scalar','finite','positive'});
assert(model.schema_version==1 && ...
    isequal(string(model.coefficient_order),["g","b","c","alpha"]), ...
    'accelff:Schema','Unknown map schema or coefficient order.');
grid=model.grid; validateattributes(grid,{'double'},{'column','finite','increasing'});
assert(numel(grid)>=2 && isequal(size(model.coefficients),[numel(grid),4]) && ...
    isequal(size(model.bounds),[numel(grid),4]) && islogical(model.valid) && isequal(size(model.valid),[numel(grid),1]), ...
    'accelff:Schema','Invalid map dimensions.');
moving=abs(v)>limits.velocity_floor;
raw=baseline; weight=zeros(size(v));
if gain>0
    for k=find(moving)'
        right=find(grid>=x(k),1);
        left=find(grid<=x(k),1,'last');
        assert(~isempty(left) && ~isempty(right),'accelff:Coverage','Position is outside map.');
        assert(all(model.valid([left,right])),'accelff:Coverage','Cannot interpolate across an invalid map cell.');
        bounds=model.bounds([left,right],:);
        assert(all(isfinite(bounds(:))) && v(k)>=max(bounds(:,1))-1e-12 && ...
            v(k)<=min(bounds(:,2))+1e-12 && a(k)>=max(bounds(:,3))-1e-12 && ...
            a(k)<=min(bounds(:,4))+1e-12,'accelff:Envelope', ...
            'Velocity/acceleration lies outside adjacent training envelopes.');
        if left==right
            b=model.coefficients(left,:);
        else
            u=(x(k)-grid(left))/(grid(right)-grid(left));
            b=(1-u)*model.coefficients(left,:)+u*model.coefficients(right,:);
        end
        assert(all(isfinite(b)),'accelff:Coefficients','Nonfinite map coefficients.');
        proposal=b*[1;v(k);sign(v(k));a(k)];
        u=min(1,(abs(v(k))-limits.velocity_floor)/limits.velocity_floor);
        weight(k)=gain*u^2*(3-2*u); % continuous blend near excluded stops
        raw(k)=baseline(k)+weight(k)*(proposal-baseline(k));
    end
end
% No circular wrap, and no second compensation for the one-sample logging lag.
f=[raw(advance+1:end);repmat(raw(end),advance,1)];
assert(all(isfinite(f)) && max(abs(f))<=limits.ff_A, ...
    'accelff:FFLimit','FF exceeds its reserved current budget; do not clip.');
assert(max(abs(diff(f)))/Ts<=limits.ff_slew_A_s, ...
    'accelff:FFSlew','FF slew exceeds the approved limit.');
detail=struct('raw',raw,'blend',weight,'advance_samples',advance, ...
    'peak_A',max(abs(f)),'slew_A_s',max(abs(diff(f)))/Ts);
end
