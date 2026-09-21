function tests = test_acceleration_ff
% Offline checks. Startup loads model settings but never connects or captures.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root,'src'));
end

function testStartupFromTemporaryCopy(testCase)
% Run preparation from a Live Editor-style temporary copy; stop before build.
root = fileparts(fileparts(mfilename('fullpath')));
source = fileread(fullfile(root,'exp05_AccelerationFF','acceleration_ff_experiment.m'));
sectionEnd = strfind(source, '%[text] ## 3. Build the tunable model');
assertNotEmpty(testCase, sectionEnd);
folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
scriptPath = fullfile(folder.Folder,'acceleration_ff_startup.m');
fid = fopen(scriptPath,'w');
fprintf(fid,'%s',source(1:sectionEnd-1));
fclose(fid);

% The settings script saves its MAT file; preserve the user's existing copy.
configPath = fullfile(root,'config','data','config_tunable.mat');
backupPath = fullfile(folder.Folder,'config_before.mat');
copyfile(configPath,backupPath);
configGuard = onCleanup(@()copyfile(backupPath,configPath));
previousFolder = pwd;
folderGuard = onCleanup(@()cd(previousFolder));
cd(folder.Folder);

actual = run_startup_copy(scriptPath);
verifyEqual(testCase,actual.root,root);
verifyTrue(testCase,isfile(actual.plantPath));
verifyEqual(testCase,actual.Ts,actual.plantTs);
verifyEqual(testCase,actual.feedbackFlag,1);
verifyEqual(testCase,actual.dist,1.25);
verifyEqual(testCase,actual.endCount,66600000);
verifyLessThan(testCase,actual.endCount,66655810);
verifyLessThan(testCase,actual.sensitivityPeak,2);
verifyLessThanOrEqual(testCase,actual.peakSpeeds,actual.speedLimits);
verifyGreaterThan(testCase,max(actual.peakSpeeds),1.99);
verifyEqual(testCase,numel(actual.peakSpeeds),8);
verifyLessThanOrEqual(testCase,actual.sampleCounts,tunable_trajectory_buffer_capacity());
verifyEqual(testCase,actual.Ntrial,80);
verifyEqual(testCase,actual.Fc,420);
verifyEqual(testCase,actual.teacherOptions.minTrials,5);
verifyEqual(testCase,actual.teacherOptions.maxInput,2);
end

function actual = run_startup_copy(scriptPath)
% Isolate the script's clear from the test workspace and cleanup guards.
run(scriptPath);
actual = struct('root',projectRoot,'plantPath',plantPath, ...
    'Ts',Ts,'plantTs',plant.Ts,'feedbackFlag',feedbackFlag, ...
    'dist',max(allProfiles{1}.pos),'endCount',endCount,'sensitivityPeak',sensitivityPeak, ...
    'peakSpeeds',cellfun(@(p)max(abs(p.vel)),allProfiles), ...
    'speedLimits',allSpeeds,'sampleCounts',cellfun(@(p)numel(p.pos),allProfiles), ...
    'Ntrial',Ntrial,'Fc',Fc,'teacherOptions',teacherOptions);
end

function testConstrainedUpdateMatchesClosedLoopPrediction(testCase)
Ts = .00025; t = (0:3000)'*Ts;
[~,model] = modelCreate(struct('m',.07,'d',.2,'k',0,'delay',8,'lp',[0,0,0]),Ts,(1:10)');
P = model.model*tf(1,[1,zeros(1,model.delay)],Ts);
fb = struct('PI',tf(30,1,Ts),'K',tf(30,1,Ts),'zp',[0,0,0],'lp',[0,0,0]);
desiredCurrent = 1.6*exp(-((t-.25)/.035).^2);
u = min(desiredCurrent+.6*exp(-((t-.25)/.01).^2),2);
u = u+.05*sin(2*pi*1200*t).*exp(-((t-.5)/.03).^2);
e = lsim(P,desiredCurrent-u,t);
effectiveFF = u-lsimFB(fb,e,t);
history = struct('t',t,'u',u,'e',e, ...
    'f',[effectiveFF(2:end);effectiveFF(end)]);
[z,p,k] = butter(4,420/(1/(2*Ts))); [sos,g] = zp2sos(z,p,k);
[fNext,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2);
verifyLessThan(testCase,rms(diagnostic.predictedError),.3*rms(e));
verifyLessThanOrEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.85+1e-6);
verifyLessThan(testCase,diagnostic.constraintResidual,1e-6);
frequency = (0:numel(t)-1)'/(numel(t)*Ts);
high = frequency>800 & frequency<1/Ts-800;
% Window the finite record so endpoint discontinuities are not counted as
% the injected high-frequency current ripple.
window = hann(numel(t),'periodic');
before = fft(window.*u); after = fft(window.*diagnostic.predictedCurrent);
verifyLessThan(testCase,norm(after(high)),.1*norm(before(high)));
effectiveFF = u-lsimFB(fb,e,t);
loggedFF = [0;fNext(1:end-1)];
replayedError = e-lsim(feedback(P,fb.PI),loggedFF-effectiveFF,t);
verifyEqual(testCase,replayedError,diagnostic.predictedError,'AbsTol',1e-8);
% Mean-error updates keep the late-learning rate without fabricating trials.
[gentle,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2,.3);
verifyEqual(testCase,diagnostic.rate,.3);
verifyLessThanOrEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.85+1e-6);
replayedError = e-lsim(feedback(P,fb.PI),[0;gentle(1:end-1)]-effectiveFF,t);
verifyEqual(testCase,replayedError,diagnostic.predictedError,'AbsTol',1e-8);
% A feasible update must keep the existing Q-filtered learning law exactly.
history.u = .2*sin(2*pi*20*t).*window;
history.e = zeros(size(t));
history.f = [history.u(2:end);history.u(end)];
[unchanged,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2);
verifyEqual(testCase,unchanged,filtfilt_clean(sos,g,history.f),'AbsTol',1e-12);
verifyEqual(testCase,diagnostic.iterations,0);
% Localized learning is weighted before the same Q filter and current check.
history.e = 1e-6*sin(2*pi*5*t).*window;
history.u = [0;history.f(1:end-1)]+lsimFB(fb,history.e,t);
learningWeight = min(max((t-.1)/.1,0),1);
learningWeight = learningWeight.^2.*(3-2*learningWeight);
[localized,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2,.3,learningWeight);
expected = filtfilt_clean(sos,g,history.f+.3*learningWeight.* ...
    (lsimFB(fb,history.e,t)+lsimInvModel(model,history.e)));
verifyEqual(testCase,localized,expected,'AbsTol',1e-12);
verifyEqual(testCase,diagnostic.learningWeight,learningWeight);
verifyLessThanOrEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.85+1e-6);
[responsive,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2,.6,learningWeight);
expected = filtfilt_clean(sos,g,history.f+.6*learningWeight.* ...
    (lsimFB(fb,history.e,t)+lsimInvModel(model,history.e)));
verifyEqual(testCase,responsive,expected,'AbsTol',1e-12);
verifyLessThanOrEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.85+1e-6);
end

function testConstrainedUpdateAllowsOpposedFeedback(testCase)
Ts = .00025; t = (0:3000)'*Ts;
[~,model] = modelCreate(struct('m',.07,'d',100,'k',0,'delay',8,'lp',[0,0,0]),Ts,(1:10)');
fb = struct('PI',tf(4000,1,Ts),'K',tf(4000,1,Ts),'zp',[0,0,0],'lp',[0,0,0]);
shape = sin(pi*t/t(end)).^2;
e = .0025*shape; u = .2*shape;
effectiveFF = u-lsimFB(fb,e,t);
history = struct('t',t,'u',u,'e',e,'f',[effectiveFF(2:end);effectiveFF(end)]);
[z,p,k] = butter(4,420/(1/(2*Ts))); [sos,g] = zp2sos(z,p,k);
[fNext,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2,.3);
verifyGreaterThan(testCase,max(abs(fNext)),4);
verifyLessThanOrEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.85+1e-6);
verifyLessThan(testCase,diagnostic.constraintResidual,1e-6);
end

function testProfileDerivativesAndReturn(testCase)
Ts = 0.001;
traj = generate_acceleration_profile(0.84,4,-0.65,Ts,[0,0,0]);
n = (numel(traj.time)+1)/2;
verifyEqual(testCase,traj.pos([1,n,end]),[0;0.84;0],'AbsTol',1e-12);
verifyEqual(testCase,traj.vel(1:n),-flipud(traj.vel(n:end)),'AbsTol',1e-12);
verifyEqual(testCase,traj.acc(1:n),flipud(traj.acc(n:end)),'AbsTol',1e-12);
ix = 10:n-10;
verifyEqual(testCase,(traj.pos(ix+1)-traj.pos(ix-1))/(2*Ts), ...
    traj.vel(ix),'AbsTol',1e-6);
verifyEqual(testCase,(traj.vel(ix+1)-traj.vel(ix-1))/(2*Ts), ...
    traj.acc(ix),'AbsTol',1e-6);
% A long round trip also fits the deployed buffer at 8 kHz.
traj = generate_acceleration_profile(0.84,6,0.65,1/8000,[1.5,1,1.5]);
verifyLessThanOrEqual(testCase,numel(traj.pos),tunable_trajectory_buffer_capacity());
end

function testIdentificationFromDelayedMeasurements(testCase)
origin = 5.41; Ts = 0.001; delay = 8;
durations = [4,4,5,5,6,6]; warps = [-.65,.65,-.65,.65,-.65,.65];
training = cell(1,numel(durations));
for k = 1:numel(training)
    traj = generate_acceleration_profile(.84,durations(k),warps(k),Ts,[.1,.1,.1]);
    x = origin+traj.pos;
    beta = known_coefficients(x,origin);
    current = sum(beta.*[ones(size(x)),traj.vel,sign(traj.vel),traj.acc],2);
    training{k} = struct('passed',true, 'method',"ilc_teacher", 'profileIndex',k, ...
        'teacher',struct('converged',true,'currentKind',"ilc_ff_A"), ...
        'currentOffsetSamples',-delay, ...
        'y_absolute_ex',x, 'ff_ex',[current(delay+1:end);repmat(current(end),delay,1)], ...
        'u_ex',.5+.1*current, ... % Deliberately different: total current must not be fitted.
        'count_ex',(1:numel(x))', 'r_ex',traj.pos, 'Ts',Ts);
end
xGrid = origin+(.03:.01:.81)';
map = fit_acceleration_ff(training,xGrid,41,-delay);
verifyTrue(testCase,all(map.valid));
verifyEqual(testCase,map.coefficients,known_coefficients(xGrid,origin),'AbsTol',3e-4);
verifyEqual(testCase,map.currentKind,"ilc_ff_A");
verifyTrue(testCase,all(isfinite(map.currentRange),'all'));
verifyTrue(testCase,all(map.currentRange(:,[1,3])<=map.currentRange(:,[2,4]),'all'));

% Small reverse motion during dwell is not part of the commanded return.
dithered = training;
hold = find(training{1}.r_ex==max(training{1}.r_ex));
ix = hold(30:70);
dithered{1}.y_absolute_ex(ix) = dithered{1}.y_absolute_ex(ix) + ...
    2e-4*sin(linspace(0,2*pi,numel(ix)))';
dwellMap = fit_acceleration_ff(dithered,xGrid,41,-delay);
verifyEqual(testCase,dwellMap.coefficients,map.coefficients,'AbsTol',3e-4);
% A genuine reversal inside the commanded forward pass must still be rejected.
reversed = training{1}; mid = find(reversed.r_ex>.4,1);
reversed.y_absolute_ex(mid:mid+40) = reversed.y_absolute_ex(mid:mid+40)-.03;
verifyError(testCase,@()fit_acceleration_ff({reversed},xGrid,41,-delay), ...
    'NikonMotor:NonmonotoneTraining');

rejected = training{1}; rejected.method = "fb";
verifyError(testCase,@()fit_acceleration_ff({rejected},xGrid,41,-delay), ...
    'NikonMotor:InvalidTrainingRun');
rejected = training{1}; rejected.teacher.converged = false;
verifyError(testCase,@()fit_acceleration_ff({rejected},xGrid,41,-delay), ...
    'NikonMotor:InvalidTrainingRun');

% An unseen duration/warp must predict the learned FF in the interior.
traj = generate_acceleration_profile(.84,4.5,.25,Ts,[.1,.1,.1]);
f = acceleration_feedforward(map,traj,origin,zeros(size(traj.pos)),1,.02);
x = origin+traj.pos;
expected = sum(known_coefficients(x,origin).* ...
    [ones(size(x)),traj.vel,sign(traj.vel),traj.acc],2);
interior = x>xGrid(1)+.02 & x<xGrid(end)-.02 & abs(traj.vel)>.004;
verifyEqual(testCase,f(interior),expected(interior),'AbsTol',3e-4);

% Repeated measurements of one shape do not make a four-coefficient fit.
repeated = fit_acceleration_ff(repmat(training(1),1,6),xGrid,41,-delay);
verifyFalse(testCase,any(repeated.valid));
end

function testMapCoverageBlendAndMissingSamples(testCase)
map = struct('x',[0;.5;1], 'coefficients',repmat([.1,.2,.3,.4],3,1));
traj = struct('pos',[-.1;0;.25;.75;1;1.1], ...
    'vel',.1*ones(6,1), 'acc',.2*ones(6,1));
baseline = .05*ones(6,1);
f = acceleration_feedforward(map,traj,0,baseline,.5,.1);
verifyEqual(testCase,f,[.05;.05;.275;.275;.05;.05],'AbsTol',1e-12);
map.coefficients(2,:) = NaN;
verifyError(testCase,@()acceleration_feedforward(map,traj,0,baseline,1,.1), ...
    'NikonMotor:InvalidAccelerationMap');
verifyEqual(testCase,acceleration_feedforward(map,traj,0,baseline,0,.1),baseline);
data = struct('passed',true, 'method',"ilc_teacher", 'profileIndex',1, ...
    'teacher',struct('converged',true,'currentKind',"ilc_ff_A"), ...
    'currentOffsetSamples',0, ...
    'Ts',.001, 'y_absolute_ex',(1:100)', 'ff_ex',zeros(100,1), ...
    'count_ex',[1:50,52:101]);
verifyError(testCase,@()fit_acceleration_ff({data},[0;1],41,0), ...
    'NikonMotor:InvalidTrainingData');
end

function testMeasuredCurrentRangeBeforeBlending(testCase)
map = struct('x',[0;.5;1], 'coefficients',repmat([0,0,4,0],3,1), ...
    'currentRange',[-3,-1,1,3;-2.8,-1,1,2.8;-2.6,-1,1,2.6]);
traj = struct('pos',[.25;.75;.25;.75;0;1], ...
    'vel',[1;1;-1;-1;1;1], 'acc',zeros(6,1));
baseline = .1*ones(6,1);
f = acceleration_feedforward(map,traj,0,baseline,.5,.1);
verifyEqual(testCase,f,[1.5;1.4;-1.4;-1.3;.1;.1],'AbsTol',1e-12);
% The measured range may exceed 2 A; it is not a fixed FB capacity reserve.
f = acceleration_feedforward(map,traj,0,baseline,1,.1);
verifyEqual(testCase,f,[2.9;2.7;-2.9;-2.7;.1;.1],'AbsTol',1e-12);
map.currentRange(:,1) = 1;
verifyError(testCase,@()acceleration_feedforward(map,traj,0,baseline,1,.1), ...
    'NikonMotor:InvalidAccelerationMap');
end

function testTeacherConvergenceAndCaptureRejection(testCase)
[history,velocity,settings] = teacher_fixture();
teacher = evaluate_ilc_teacher(history,5,velocity,settings);
verifyTrue(testCase,teacher.converged);
verifyEqual(testCase,teacher.currentKind,"ilc_ff_A");
verifyEqual(testCase,teacher.feedbackRatio(end),.05,'AbsTol',1e-12);
verifyEqual(testCase,teacher.iterations,5);
teacher = evaluate_ilc_teacher(history,4,velocity,settings);
verifyFalse(testCase,teacher.converged);

% Learned FF may exceed 2 A when feedback opposes it and the total is unsaturated.
opposed = history;
opposed.f(:,2:5) = 2.2;
opposed.ff(:,2:5) = [zeros(1,4);opposed.f(1:end-1,2:5)];
opposed.u(:,2:5) = opposed.ff(:,2:5)*(1.8/2.2);
teacher = evaluate_ilc_teacher(opposed,5,velocity,settings);
verifyTrue(testCase,teacher.converged);
opposed.u(30,2) = settings.maxInput;
teacher = evaluate_ilc_teacher(opposed,5,velocity,settings);
verifyTrue(testCase,teacher.converged);
verifyEqual(testCase,teacher.saturatedSamples,[0,1,0,0,0]);

% Unapplied candidates do not affect convergence or enter the teacher data.
history.f(:,6) = 100;
teacher = evaluate_ilc_teacher(history,5,velocity,settings);
verifyTrue(testCase,teacher.converged);
bad = history;
bad.f(:,5) = .4; bad.ff(:,5) = [0;bad.f(1:end-1,5)];
bad.u(:,5) = bad.ff(:,5)+.01;
teacher = evaluate_ilc_teacher(bad,5,velocity,settings);
verifyFalse(testCase,teacher.converged);
bad = history; bad.u(:,5) = bad.ff(:,5)+.1;
teacher = evaluate_ilc_teacher(bad,5,velocity,settings);
verifyFalse(testCase,teacher.converged);
bad = history;
moving = abs([0;velocity(1:end-1)])>.002;
bad.e(moving,5) = 1e-3;
bad.y(:,5) = bad.r(:,5)-bad.e(:,5);
teacher = evaluate_ilc_teacher(bad,5,velocity,settings);
verifyFalse(testCase,teacher.converged);
% A clipped latest trial must keep learning; exceeding the target limit is invalid.
bad = history; bad.u(30,5) = -2;
teacher = evaluate_ilc_teacher(bad,5,velocity,settings);
verifyFalse(testCase,teacher.converged);
verifyEqual(testCase,teacher.saturatedSamples,[0,0,0,0,1]);
bad.u(30,2) = 2.01;
verifyError(testCase,@()evaluate_ilc_teacher(bad,5,velocity,settings), ...
    'NikonMotor:CurrentLimitExceeded');
bad = history; bad.count(50:end,2) = bad.count(50:end,2)+1;
verifyError(testCase,@()evaluate_ilc_teacher(bad,5,velocity,settings), ...
    'NikonMotor:LostSamples');
bad = history; bad.ff(30,2) = .3;
verifyError(testCase,@()evaluate_ilc_teacher(bad,5,velocity,settings), ...
    'NikonMotor:CaptureMismatch');
bad = history; bad.y_absolute(30,2) = settings.endPosition+.01;
verifyError(testCase,@()evaluate_ilc_teacher(bad,5,velocity,settings), ...
    'NikonMotor:TrackingFailed');
bad = history; bad.e(end,2) = -2e-4; bad.y(end,2) = bad.r(end,2)-bad.e(end,2);
verifyError(testCase,@()evaluate_ilc_teacher(bad,5,velocity,settings), ...
    'NikonMotor:TrackingFailed');
end

function testTeacherRequiresMeasuredFixedFFValidation(testCase)
[history,velocity,settings] = teacher_fixture();
for name = ["count","r","f","ff","u","e","y","y_absolute"]
    history.(name)(:,6:24) = repmat(history.(name)(:,5),1,19);
end
settings.averagingWindow = 8; settings.validationTrials = 8;
noisy = history;
noisy.f(:,9:16) = noisy.f(:,9:16)+.03*(-1).^(9:16);
noisy.ff(:,9:16) = [zeros(1,8);noisy.f(1:end-1,9:16)];
noisy.u(:,9:16) = noisy.ff(:,9:16)+.01;
teacher = evaluate_ilc_teacher(noisy,16,velocity,settings);
verifyGreaterThan(testCase,teacher.ffPlateau,settings.ffRelativeChange);
verifyTrue(testCase,teacher.validationReady);
verifyFalse(testCase,teacher.converged); % Readiness is not acceptance.
teacher = evaluate_ilc_teacher(history,16,velocity,settings);
verifyTrue(testCase,teacher.validationReady);
verifyFalse(testCase,teacher.converged);
history.validationStart = 17;
history.validationFF = mean(history.f(:,9:16),2);
teacher = evaluate_ilc_teacher(history,23,velocity,settings);
verifyFalse(testCase,teacher.converged);
verifyFalse(testCase,teacher.meanUpdateReady);
teacher = evaluate_ilc_teacher(history,24,velocity,settings);
verifyTrue(testCase,teacher.converged);
verifyEqual(testCase,teacher.validationTrials,8);
% A correction from the measured mean error is also a valid candidate, but
% only after the same candidate has actually been captured eight times.
corrected = history; corrected.validationFF = .25*ones(size(history.f,1),1);
corrected.f(:,17:24) = repmat(corrected.validationFF,1,8);
corrected.ff(:,17:24) = [zeros(1,8);corrected.f(1:end-1,17:24)];
corrected.u(:,17:24) = corrected.ff(:,17:24)+.01;
teacher = evaluate_ilc_teacher(corrected,23,velocity,settings);
verifyFalse(testCase,teacher.converged);
teacher = evaluate_ilc_teacher(corrected,24,velocity,settings);
verifyTrue(testCase,teacher.converged);
bad = history; bad.u(30,18) = 2;
teacher = evaluate_ilc_teacher(bad,24,velocity,settings);
verifyFalse(testCase,teacher.converged);
verifyTrue(testCase,teacher.relearnRequired);
verifyFalse(testCase,teacher.meanUpdateReady); % Saturation requires ordinary relearning.
bad = history; bad.e(:,24) = 1.3*bad.e(:,24);
bad.y(:,24) = bad.r(:,24)-bad.e(:,24);
teacher = evaluate_ilc_teacher(bad,24,velocity,settings);
verifyFalse(testCase,teacher.converged); % Averaging must not bypass the RMS gate.
bad = history; bad.f(:,24) = bad.f(:,24)+1e-4;
bad.ff(:,24) = [0;bad.f(1:end-1,24)];
verifyError(testCase,@()evaluate_ilc_teacher(bad,24,velocity,settings), ...
    'NikonMotor:ValidationFFChanged');
settings.rmsLimit = 11e-6; settings.movingRmsLimit = 11e-6;
settings.peakErrorLimit = 11e-6;
teacher = evaluate_ilc_teacher(history,24,velocity,settings);
verifyTrue(testCase,teacher.converged);
for name = ["rmsLimit","movingRmsLimit","peakErrorLimit"]
    strict = settings; strict.(name) = 1e-6;
    teacher = evaluate_ilc_teacher(history,24,velocity,strict);
    verifyFalse(testCase,teacher.accuracyPassed);
    verifyFalse(testCase,teacher.converged);
    verifyTrue(testCase,teacher.relearnRequired);
    verifyTrue(testCase,teacher.meanUpdateReady); % Stable, inaccurate, fixed measurements.
end
drifting = history; drifting.e(:,24) = 1.3*drifting.e(:,24);
drifting.y(:,24) = drifting.r(:,24)-drifting.e(:,24);
strict = settings; strict.movingRmsLimit = 1e-6;
teacher = evaluate_ilc_teacher(drifting,24,velocity,strict);
verifyTrue(testCase,teacher.relearnRequired);
verifyTrue(testCase,teacher.meanUpdateReady); % An inaccurate block must not stall learning.
verifyFalse(testCase,teacher.converged); % RMS variation still prevents acceptance.
% Starting a new candidate with fewer than eight trials left guarantees failure.
limited = strict; limited.maxTrials = 31;
teacher = evaluate_ilc_teacher(history,24,velocity,limited);
verifyFalse(testCase,teacher.meanUpdateReady);
verifyFalse(testCase,teacher.converged);
limited.maxTrials = 32;
teacher = evaluate_ilc_teacher(history,24,velocity,limited);
verifyTrue(testCase,teacher.meanUpdateReady);
pending = history; pending.validationStart = 0;
limited.maxTrials = 23;
teacher = evaluate_ilc_teacher(pending,16,velocity,limited);
verifyFalse(testCase,teacher.validationReady);
% A completed, accurate block may still pass exactly at the budget boundary.
limited = settings; limited.maxTrials = 24;
teacher = evaluate_ilc_teacher(history,24,velocity,limited);
verifyTrue(testCase,teacher.converged);
bad = history; bad.e(:,18) = 2*bad.e(:,18);
bad.y(:,18) = bad.r(:,18)-bad.e(:,18);
teacher = evaluate_ilc_teacher(bad,24,velocity,settings);
verifyEqual(testCase,teacher.errorPlateau,0);
verifyFalse(testCase,teacher.accuracyPassed); % A good final trial cannot hide a poor repeat.
bad = history; bad.e(:,24) = 1.3*bad.e(:,24);
bad.y(:,24) = bad.r(:,24)-bad.e(:,24);
singleRms = settings; singleRms.peakErrorLimit = 20e-6;
teacher = evaluate_ilc_teacher(bad,24,velocity,singleRms);
verifyFalse(testCase,teacher.accuracyPassed);
verifyFalse(testCase,teacher.converged);
verifyFalse(testCase,teacher.relearnRequired); % Keep validating an otherwise accurate block.
% After a failed block, validate only an average of fresh learning trials.
history.validationStart = 0; history.learningStart = 25;
for name = ["count","r","f","ff","u","e","y","y_absolute"]
    history.(name)(:,25:32) = repmat(history.(name)(:,24),1,8);
end
teacher = evaluate_ilc_teacher(history,31,velocity,settings);
verifyFalse(testCase,teacher.validationReady);
teacher = evaluate_ilc_teacher(history,32,velocity,settings);
verifyTrue(testCase,teacher.validationReady);
verifyFalse(testCase,teacher.converged);
end

function testFixedAccuracyAcceptsSmallVariationButRejectsOnePoorRepeat(testCase)
[history,velocity,settings] = teacher_fixture();
for name = ["count","r","f","ff","u","e","y","y_absolute"]
    history.(name)(:,6:24) = repmat(history.(name)(:,5),1,19);
end
settings.averagingWindow = 8; settings.validationTrials = 8;
settings.rmsLimit = 10e-6; settings.movingRmsLimit = 10e-6; settings.peakErrorLimit = 100e-6;
history.validationStart = 17; history.validationFF = mean(history.f(:,9:16),2);
history.e(:,17:24) = repmat(1e-6*[2 4 2 4 2 4 2 4],size(history.e,1),1);
history.y = history.r-history.e;
teacher = evaluate_ilc_teacher(history,24,velocity,settings);
verifyFalse(testCase,teacher.converged);
settings.requireRmsPlateau = false;
teacher = evaluate_ilc_teacher(history,24,velocity,settings);
verifyTrue(testCase,teacher.converged);
history.e(:,18) = 15e-6; history.y = history.r-history.e;
teacher = evaluate_ilc_teacher(history,24,velocity,settings);
verifyLessThan(testCase,teacher.accuracyRms,settings.rmsLimit);
verifyFalse(testCase,teacher.accuracyPassed);
verifyFalse(testCase,teacher.converged);
end

function testTeacherMarginUsesConfiguredCurrentBound(testCase)
Ts = .00025; t = (0:3000)'*Ts;
[~,model] = modelCreate(struct('m',.07,'d',.2,'k',0,'delay',8,'lp',[0,0,0]),Ts,(1:10)');
P = model.model*tf(1,[1,zeros(1,model.delay)],Ts);
fb = struct('PI',tf(30,1,Ts),'K',tf(30,1,Ts),'zp',[0,0,0],'lp',[0,0,0]);
desired = 2.1*exp(-((t-.25)/.035).^2); u = min(desired,2);
e = lsim(P,desired-u,t); effective = u-lsimFB(fb,e,t);
history = struct('t',t,'u',u,'e',e,'f',[effective(2:end);effective(end)], ...
    'teacher',struct('settings',struct('currentMargin',.04)));
[z,p,k] = butter(4,420/(1/(2*Ts))); [sos,g] = zp2sos(z,p,k);
[fNext,diagnostic] = update_ilc_constrained(history,1,model,fb,sos,g,2);
verifyEqual(testCase,diagnostic.currentBound,1.96,'AbsTol',1e-12);
verifyEqual(testCase,max(abs(diagnostic.predictedCurrent)),1.96,'AbsTol',1e-5);
verifyLessThan(testCase,max(abs(fNext)),4);
end

function testResumeRetainsAppliedHistoryAndRejectsChangedSetup(testCase)
[history,velocity,settings] = teacher_fixture();
history.t = (0:numel(velocity)-1)'*.001;
history.eNorm = vecnorm(history.e); history.alpha = .9.^(1:5);
traj = struct('pos',history.reference,'time',history.t,'vel',velocity);
runtime = struct('Ts',.001,'Fc',420,'Qsos',1,'Qscale',1, ...
    'Kd',tf(1,1,.001),'Ndelay',8,'plantPath',"fixture");
data = runtime; data.method = "ilc_teacher"; data.history = history;
data.completedTrials = 5;
data.captures = {struct('trial',1,'data',[1 2 3])};
[resumed,first] = resume_ilc_teacher_history(data,traj,8,settings,runtime);
verifyEqual(testCase,first,6);
verifyEqual(testCase,resumed.captures,data.captures);
for name = ["count","r","f","ff","e","u","y","y_absolute"]
    verifyEqual(testCase,resumed.(name)(:,1:5),history.(name));
end
verifyEqual(testCase,resumed.r(:,6:8),repmat(traj.pos,1,3));
verifyEqual(testCase,resumed.f(:,6),history.f(:,5));
verifyTrue(testCase,all(isnan(resumed.alpha(6:8))));
changed = runtime; changed.Fc = 40;
verifyError(testCase,@()resume_ilc_teacher_history(data,traj,8,settings,changed), ...
    'NikonMotor:TeacherResumeMismatch');
changed = traj; changed.pos(20) = changed.pos(20)+1e-5;
verifyError(testCase,@()resume_ilc_teacher_history(data,changed,8,settings,runtime), ...
    'NikonMotor:TeacherResumeMismatch');
bad = data; bad.history.count(20,3) = bad.history.count(20,3)+1;
verifyError(testCase,@()resume_ilc_teacher_history(bad,traj,8,settings,runtime), ...
    'NikonMotor:LostSamples');
for name = ["count","r","f","ff","e","u","y","y_absolute"]
    history.(name)(:,6:24) = repmat(history.(name)(:,5),1,19);
end
history.eNorm = vecnorm(history.e); history.alpha = nan(1,24);
history.validationStart = 17; history.validationStarts = 17;
history.validationFF = history.f(:,24);
settings.averagingWindow = 8; settings.validationTrials = 8;
data.history = history; data.completedTrials = 24;
[resumed,first] = resume_ilc_teacher_history(data,traj,40,settings,runtime);
verifyEqual(testCase,first,25);
verifyEqual(testCase,resumed.validationStart,25);
verifyEqual(testCase,resumed.validationStarts,[17,25]);
verifyEqual(testCase,resumed.validationFF,history.f(:,24));
verifyEqual(testCase,resumed.teacher.validationTrials,0);
verifyFalse(testCase,resumed.teacher.meanUpdateReady);
verifyFalse(testCase,resumed.teacher.converged);
verifyFalse(testCase,resumed.teacher.accuracyPassed);
end

function [history,velocity,settings] = teacher_fixture()
traj = generate_acceleration_profile(.1,1,.2,.001,[.1,.1,.1]);
N = numel(traj.pos); velocity = traj.vel;
r = [0;traj.pos(1:end-1)];
f = repmat(.2*ones(N,1),1,5);
f(:,1) = 0; % Zero initialization is required only on the first trial.
ff = [zeros(1,5);f(1:end-1,:)];
e = repmat(1e-5*double(abs([0;velocity(1:end-1)])>.002),1,5);
history = struct('reference',traj.pos,'count',repmat((1:N)',1,5), ...
    'r',repmat(r,1,5),'f',f,'ff',ff,'u',ff+.01,'e',e, ...
    'y',repmat(r,1,5)-e,'y_absolute',5.41+repmat(r,1,5)-e);
settings = struct('minTrials',5,'window',3,'errorRelativeChange',.05, ...
    'ffRelativeChange',.05,'feedbackRatio',.2,'trackingLimit',.003, ...
    'terminalLimit',.0001,'maxInput',2,'endPosition',6.665581);
end

function beta = known_coefficients(x,origin)
p = x-origin;
beta = [.05+.01*p, .2+.02*p, .05+.01*p, .3+.03*p];
end
