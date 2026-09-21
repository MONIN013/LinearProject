function f = acceleration_feedforward(map, traj, origin, baseline, gain, blendDistance)
%ACCELERATION_FEEDFORWARD Blend a position map into TOTAL FF, before time advance.
% Outside the fitted position interval and at rest use the existing baseline.
% alpha*a already includes inertia; do not add a second inertia FF afterwards.
validateattributes(gain, {'double'}, {'scalar','finite','>=',0,'<=',1});
validateattributes(blendDistance, {'double'}, {'scalar','finite','positive'});
validateattributes(origin, {'double'}, {'scalar','finite'});
validateattributes(map.x, {'double'}, {'column','finite','increasing','numel',size(map.coefficients,1)});
x = origin+traj.pos(:); v = traj.vel(:); a = traj.acc(:);
validateattributes(baseline, {'double'}, {'column','finite','numel',numel(x)});
assert(numel(map.x)>=2 && size(map.coefficients,2)==4 && ...
    numel(v)==numel(x) && numel(a)==numel(x) && all(isfinite([x;v;a])), ...
    'NikonMotor:InvalidAccelerationFF', 'Invalid trajectory or map dimensions.');
f = baseline;
if gain==0, return; end
active = x>map.x(1) & x<map.x(end) & abs(v)>0.002;
beta = interp1(map.x, map.coefficients, x(active), 'linear', NaN);
assert(all(isfinite(beta),'all'), 'NikonMotor:InvalidAccelerationMap', ...
    'An interior map cell is unidentified. Inspect the coefficient plot.');
proposal = sum(beta.*[ones(sum(active),1),v(active),sign(v(active)),a(active)],2);
if isfield(map,'currentRange')
    % A least-squares coefficient combination can exceed every measured
    % teacher current even between training speeds. Retain their local range.
    limits = interp1(map.x,map.currentRange,x(active),'linear',NaN);
    lowerColumn = 1+2*(v(active)>0);
    lower = limits(sub2ind(size(limits),(1:sum(active))',lowerColumn));
    upper = limits(sub2ind(size(limits),(1:sum(active))',lowerColumn+1));
    assert(all(isfinite([lower;upper])) && all(lower<=upper), ...
        'NikonMotor:InvalidAccelerationMap','Invalid measured teacher current range.');
    proposal = min(max(proposal,lower),upper);
end
% Smoothly join the mapped interval to the baseline at its two ends and stops.
w = min([ones(sum(active),1), (x(active)-map.x(1))/blendDistance, ...
    (map.x(end)-x(active))/blendDistance, (abs(v(active))-0.002)/0.002],[],2);
w = gain*w.^2.*(3-2*w);
f(active) = baseline(active)+w.*(proposal-baseline(active));
end
