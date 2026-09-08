function p = profile(distance, duration, warp, Ts, dwell)
%PROFILE Analytic C2 rest-to-rest round trip; no Symbolic Toolbox or device I/O.
% duration is ONE-WAY motion time, rounded UP to an integer sample count.
% dwell = [before, at reversal, after] [s]. abs(warp)<=1 changes where the
% acceleration occurs without changing endpoints. Check hardware limits later.
validateattributes(distance,{'double'},{'scalar','finite','positive'});
validateattributes(Ts,{'double'},{'scalar','finite','positive'});
validateattributes(duration,{'double'},{'scalar','finite','>=',4*Ts});
validateattributes(warp,{'double'},{'scalar','finite','>=',-1,'<=',1});
validateattributes(dwell,{'double'},{'vector','numel',3,'finite','nonnegative'});
T = ceil(duration/Ts)*Ts;
s = (0:round(T/Ts))'*Ts/T;
u = s + warp*(s.^2-2*s.^3+s.^4);
u1 = 1 + warp*(2*s-6*s.^2+4*s.^3);
u2 = warp*(2-12*s+12*s.^2);
u3 = warp*(-12+24*s);
h = 10*u.^3-15*u.^4+6*u.^5;
h1 = 30*u.^2-60*u.^3+30*u.^4;
h2 = 60*u-180*u.^2+120*u.^3;
h3 = 60-360*u+360*u.^2;
x = distance*h;
v = distance*h1.*u1/T;
a = distance*(h2.*u1.^2+h1.*u2)/T^2;
j = distance*(h3.*u1.^3+3*h2.*u1.*u2+h1.*u3)/T^3;
forward = [x,v,a,j];
backward = flipud(forward).*[1,-1,1,-1];
% Remove duplicate time points at phase boundaries. Time reversal changes the
% signs of velocity and jerk, NOT acceleration at the same physical position.
nb = ceil(dwell(1)/Ts); nr = ceil(dwell(2)/Ts); ne = ceil(dwell(3)/Ts);
z = [zeros(nb,4); forward; repmat([distance,0,0,0],nr,1); ...
     backward(2:end,:); zeros(ne,4)];
p = struct('t',(0:size(z,1)-1)'*Ts,'x',z(:,1),'v',z(:,2), ...
    'a',z(:,3),'j',z(:,4),'Ts',Ts,'duration',T,'warp',warp);
end
