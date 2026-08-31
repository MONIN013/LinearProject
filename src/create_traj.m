function r = create_traj(t,pos,vmax,amax,jmax,smax,start_time,dwell_time,repeat_n,showFig)
%create_traj - Calculate time-optimal 4th order back and forth trajectory
%https://github.com/WataruOhnishi/TrajectTools required
%
% [r, end_time] = create_traj(t,target_pos,vmax,amax,jmax,smax,start_time,dwell_time,repeat_n,showFig)
% -- input --
% t          : time units of the trajectory
% pos        : target position
% vmax       : maximum velocity
% amax       : maximum acceleration
% jmax       : maximum jerk
% smax       : maximum snap
% start_time : motion start time (default 0.1)
% dwell_time : motion dwell time (default 0)
% repeat_n   : number of back and forth (default 1)
% showFig    : show figure of generated trajectory (default true)
% -- output --
% r          : trajectory profile
%
% Author     : Kentaro Tsurumoto, The University of Tokyo, 2023
narginchk(6,10);
if nargin < 7; start_time = 0.1; end
if nargin < 8; dwell_time = 0; end
if nargin < 9; repeat_n = 1; end
if nargin < 10; showFig = true; end
r.t = t;
r.start_time = start_time;
r.dwell_time = dwell_time;

% calculate motion profile
[tmake4,dd] = make4(pos,vmax,amax,jmax,smax);
[~,~,~,~,~,~,~,tt] = profile4(tmake4,smax,tmake4(1)*1e-2,false);
% set back and forth profile
BCt1 = [start_time, start_time + tt]; % go
BCt2 = [dwell_time, dwell_time + tt]; % back
BCt = [BCt1,BCt2+BCt1(end)]; % go and back
BCtunit = BCt;
jmax2 = tmake4(1)*smax; % modified max jerk
BCj = [0, 0, jmax2, jmax2, 0, 0, -jmax2, -jmax2, 0, 0, -jmax2, -jmax2, 0, 0, jmax2, jmax2, 0];
BCj = [BCj, -BCj];
% add back and forth
for i = 2:repeat_n
    BCt = [BCt, BCt(end)+max(0,BCtunit-start_time+dwell_time)];
    BCj = [BCj, BCj];
end
end_time = BCt(end);
r.end_time = end_time;

% polynomial order for acceleration trajectory
np = 1;
% polynomial trajectory generation
BC = cell(2,1);
BC{1} = 0; % initial position
BC{2} = 0; % initial velocity
BC{3} = 0; % initial acceleration
BC{4} = BCj; % acceleration boundary conditions
trajType = 'jrk'; % for given velocity constraints 
pBasis = backandforth(trajType,BCt,BC,np,false);
% assign trajectory profile
r.p = outPolyBasis(pBasis,1,t)'; % position
r.v = outPolyBasis(pBasis,2,t)'; % velocity
r.a = outPolyBasis(pBasis,3,t)'; % acceleration
r.j = outPolyBasis(pBasis,4,t)'; % jerk
r.s = outPolyBasis(pBasis,5,t)'; % snap
% trajectory key information
r.pos = pos; % motion distance
r.vmax = max(r.v); % maximum velocity
r.amax = max(r.a); % maximum acceleration
r.jmax = max(r.j); % maximum jerk
r.smax = max(r.s); % maximum snap
if showFig
    figure;
    subplot(3,2,1);
    plot(t,r.p,'b'); hold on;
    xlabel('time [s]');
    ylabel('position [rad]');hold off;
    subplot(3,2,2);
    plot(t,r.v,'b'); hold on;
    plot([t(1),t(end)],[vmax,vmax],'r--');
    plot([t(1),t(end)],[-vmax,-vmax],'r--');
    xlabel('time [s]');
    ylabel('velocity [rad/s]');hold off;
    subplot(3,2,3);
    plot(t,r.a,'b'); hold on;
    plot([t(1),t(end)],[amax,amax],'r--');
    plot([t(1),t(end)],[-amax,-amax],'r--');
    xlabel('time [s]');
    ylabel('acceleration [rad/s$^2$]','Interpreter','latex');hold off;
    subplot(3,2,4);
    plot(t,r.j,'b'); hold on;
    plot([t(1),t(end)],[jmax,jmax],'r--');
    plot([t(1),t(end)],[-jmax,-jmax],'r--');
    xlabel('time [s]');
    ylabel('jerk [rad/s$^3$]','Interpreter','latex');hold off;
    subplot(3,2,5);
    plot(t,r.s,'b'); hold on;
    plot([t(1),t(end)],[smax,smax],'r--');
    plot([t(1),t(end)],[-smax,-smax],'r--');
    xlabel('time [s]');
    ylabel('snap [rad/s$^4$]','Interpreter','latex');hold off;
    if exist("pubfig","file"), pfig = pubfig(gcf); pfig.Dimension = [14 15];end
end
end