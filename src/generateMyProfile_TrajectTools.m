function traj = generateMyProfile_TrajectTools( ...
        posStart, posStep, velMax, accAve, dt, Tstay, TidlePre, TidlePost)
%GENERATEMYPROFILE_TRAJECTTOOLS Generate the legacy back-and-forth profile.
% Requires Symbolic Math Toolbox through backandforth/polySolve.

if nargin < 7, TidlePre = 0; end
if nargin < 8, TidlePost = 0; end

direction = sign(posStep);
distance = abs(posStep);
vmax = abs(velMax);
accel = abs(accAve);
tacc = vmax/accel;
distanceAccDec = vmax*tacc;

if distance > distanceAccDec
    tvel = distance/vmax - tacc;
else
    vmax = sqrt(accel*distance);
    tacc = vmax/accel;
    tvel = 0;
end

t0 = TidlePre;
BCt = [t0, ...
    t0+tacc, ...
    t0+tacc+tvel, ...
    t0+2*tacc+tvel, ...
    t0+2*tacc+tvel+Tstay, ...
    t0+3*tacc+tvel+Tstay, ...
    t0+3*tacc+2*tvel+Tstay, ...
    t0+4*tacc+2*tvel+Tstay];
BCv = [0, direction*vmax, direction*vmax, 0, ...
    0, -direction*vmax, -direction*vmax, 0];
BC = {0; BCv};

pBasis = backandforth("vel", BCt, BC, 3);
tMove = 0:dt:BCt(end);
position = outPolyBasis(pBasis, 1, tMove);
velocity = outPolyBasis(pBasis, 2, tMove);
acceleration = outPolyBasis(pBasis, 3, tMove);
jerk = outPolyBasis(pBasis, 4, tMove);
try
    snap = outPolyBasis(pBasis, 5, tMove);
catch
    snap = [diff(jerk)./dt, 0];
end

position = position-position(1);
position = distance/max(abs(position)+eps)*position;
position = posStart+sign(direction)*position;

if TidlePost > 0
    tPost = dt:dt:TidlePost;
    time = [tMove, tMove(end)+tPost];
    position = [position, repmat(posStart, 1, numel(tPost))];
    velocity = [velocity, zeros(1, numel(tPost))];
    acceleration = [acceleration, zeros(1, numel(tPost))];
    jerk = [jerk, zeros(1, numel(tPost))];
    snap = [snap, zeros(1, numel(tPost))];
else
    time = tMove;
end

traj = struct( ...
    "time", time(:), ...
    "pos", position(:), ...
    "vel", velocity(:), ...
    "acc", acceleration(:), ...
    "jerk", jerk(:), ...
    "snap", snap(:), ...
    "Tmove", BCt(end)-TidlePre, ...
    "dt", dt, ...
    "meta", struct("library", "TrajectTools", ...
        "type", "vel-backandforth", "np", 3, "tacc", tacc, ...
        "tvel", tvel, "vmax", direction*vmax, "Tstay", Tstay, ...
        "TidlePre", TidlePre, "TidlePost", TidlePost));
end
