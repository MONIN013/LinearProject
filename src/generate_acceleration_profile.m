function traj = generate_acceleration_profile(dist, duration, warp, Ts, dwell)
%GENERATE_ACCELERATION_PROFILE Round trip with adjustable acceleration location.
% duration: one-way time [s]; warp: time deformation [-1,1];
% dwell: [before, reversal, after] [s]. Fields match the existing FF profile.
validateattributes(dist, {'double'}, {'scalar','finite','positive'});
validateattributes(Ts, {'double'}, {'scalar','finite','positive'});
validateattributes(duration, {'double'}, {'scalar','finite','>=',4*Ts});
validateattributes(warp, {'double'}, {'scalar','finite','>=',-1,'<=',1});
validateattributes(dwell, {'double'}, {'vector','numel',3,'finite','nonnegative'});
duration = ceil(duration/Ts)*Ts;
s = (0:round(duration/Ts))'*Ts/duration;
q = s + warp*(s.^2-2*s.^3+s.^4);
q1 = 1 + warp*(2*s-6*s.^2+4*s.^3);
q2 = warp*(2-12*s+12*s.^2);
q3 = warp*(-12+24*s);
h = 10*q.^3-15*q.^4+6*q.^5;
h1 = 30*q.^2-60*q.^3+30*q.^4;
h2 = 60*q-180*q.^2+120*q.^3;
h3 = 60-360*q+360*q.^2;
forward = dist*[h, h1.*q1/duration, ...
    (h2.*q1.^2+h1.*q2)/duration^2, ...
    (h3.*q1.^3+3*h2.*q1.*q2+h1.*q3)/duration^3];
% Time reversal changes velocity/jerk signs, but preserves acceleration at x.
backward = flipud(forward).*[1,-1,1,-1];
n = ceil(dwell/Ts);
z = [zeros(n(1),4); forward; repmat([dist,0,0,0],n(2),1); ...
    backward(2:end,:); zeros(n(3),4)];
traj = struct('time',(0:size(z,1)-1)'*Ts, 'pos',z(:,1), ...
    'vel',z(:,2), 'acc',z(:,3), 'jerk',z(:,4));
end
