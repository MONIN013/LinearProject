function Kpi = designpi(d, k, Kt, w)
%designpi - design PI controller for second order system P
%
% Assuming P = Kt/(s^2 + d*s + k)
% Kpi = designpi(d, k, Kt, w)
%   w       : desired pole [rad/s]
%%%%%
Mpi = [d 0 0;
       k Kt 0;
       0 0 Kt];
wpi = [3*w; 3*w^2; w^3];
cpi = Mpi\wpi;
Kp = cpi(2); Ki = cpi(3);
% convert 2/2 order tf to pid type (optional)
Kpi = pid(Kp,Ki);
end

