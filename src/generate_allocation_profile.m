function traj = generate_allocation_profile(dist, duration, skew, Ts)
%GENERATE_ALLOCATION_PROFILE PR #2 polynomial shape, using exp03/05 field names.
validateattributes(dist,{'double'},{'scalar','finite','positive'});
validateattributes(Ts,{'double'},{'scalar','finite','positive'});
validateattributes(duration,{'double'},{'scalar','finite','>=',4*Ts});
validateattributes(skew,{'double'},{'scalar','finite','>=',-2,'<=',2});
n = ceil(duration/Ts); T = n*Ts; s = (0:n)'/n;
c = [-skew,6+3*skew,-15-3*skew,10+skew,0,0,0];
x = dist*polyval(c,s);
v = dist/T*polyval(polyder(c),s);
a = dist/T^2*polyval(polyder(polyder(c)),s);
j = dist/T^3*polyval(polyder(polyder(polyder(c))),s);
assert(all(diff(x)>=-1e-12),'NikonMotor:AllocationProfile','Nonmonotone leg.');
% The PR uses a mirrored leg, not exp05's time-reversed leg.
z = [zeros(ceil(1.5/Ts),4); [x,v,a,j]; ...
    repmat([dist,0,0,0],ceil(1/Ts),1); ...
    [dist-x(2:end),-v(2:end),-a(2:end),-j(2:end)]; zeros(ceil(1.5/Ts),4)];
traj = struct('time',(0:size(z,1)-1)'*Ts,'pos',z(:,1), ...
    'vel',z(:,2),'acc',z(:,3),'jerk',z(:,4));
end
