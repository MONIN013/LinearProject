%% 1. 設定を読み込み、既存のフィードバック制御器を設計する
clear; close all;
projectRoot = setup_project();
run(fullfile(projectRoot,"config","config_tunable.m"));
addpath(fullfile(projectRoot,"exp07_RepeatabilityILC"), ...
    fullfile(projectRoot,"exp08_PairedConfidenceILC"));
load(fullfile(projectRoot,"config","data","pana_params.mat"));
[plant,plantPath] = load_experiment_plant(projectRoot,plantDataFile,Ts);
Pd = plant.Pd;
Pd0 = struct("m",plant.Jn,"d",plant.Dn,"k",0, ...
    "delay",plant.Ndelay,"lp",[0,0,0]);
[~,Gn0] = modelCreate(Pd0,Ts,Pd.Frequency);
Pdn = Gn0.modelDelayed;
[fb,~,~] = fbDesign(Pd,Ts);
Kd = fb.K;
feedbackFlag = 1;

%% 2. 安定性・学習フィルタ・軌道と比較条件を確認する
Smax = 2;
S = feedback(1,Pd*Kd);
assert(isstable(feedback(Pdn*Kd,1)) && ...
    max(abs(S.ResponseData),[],'all')<Smax, ...
    'NikonMotor:ControllerCheckFailed', ...
    'Check stability and sensitivity before paired ILC.');
Fc = 420;
[Qz,Qp,Qgain] = butter(4,Fc/(1/(2*Ts)));
[Qsos,Qscale] = zp2sos(Qz,Qp,Qgain);
Q = zpk(Qz,Qp,Qgain,Ts);
figure; bodemag(S,bop); grid on; title('Measured feedback sensitivity');
figure; nyquistplot(Pdn*Kd,nop); hold on; nyquistplot(Pd*Kd,nop);
legend('Nominal','Measured');

dist = 1.25;
v_max = 0.3;
a_max = 12.0;
t_pause = 1.0; t_pre = 1.5; t_post = 1.5;
startCount = 54100000;
endCountLimit = 66655810;
trackingLimit = 3e-3;
terminalLimit = 100e-6;
traj = generateMyProfile_TrajectTools( ...
    0.0,dist,v_max,a_max/2,Ts,t_pause,t_pre,t_post);
t = traj.time(:); r = traj.pos(:); N = numel(r); Tend = t(end);
assert(startCount+dist/ENCODER_RESOLUTION+ ...
    (trackingLimit+terminalLimit)/ENCODER_RESOLUTION<endCountLimit, ...
    'NikonMotor:TrajectoryRange','The paired-ILC trajectory exceeds the validated range.');
prepare_tunable_trajectory_parameters(r,zeros(N,1),tunable_trajectory_buffer_capacity());
ops.L = @(x)lsimFB(fb,x,t)+lsimInvModel(Gn0,x);
ops.Q = @(x)exp07_q(x,Qsos,Qscale,Ts);

positionBinWidth = 0.01;
minAbsVelocity = 0.01;
activeMask = abs(traj.vel(:))>minAbsVelocity;
assert(any(activeMask),'NikonMotor:TrajectoryNotMoving','No moving samples in trajectory.');
x0 = min(r); nPosition = max(1,ceil((max(r)-x0)/positionBinWidth));
binIndex = min(nPosition,floor((r-x0)/positionBinWidth)+1);
binIndex = binIndex+nPosition*(traj.vel(:)<0);
binIndex(~activeMask) = 0;
ids = (1:2*nPosition)';
left = x0+mod(ids-1,nPosition)*positionBinWidth;
right = min(left+positionBinWidth,max(r));
direction = [ones(nPosition,1);-ones(nPosition,1)];
binTable = table(ids,left,right,direction, ...
    accumarray(binIndex(activeMask),1,[2*nPosition,1]), ...
    'VariableNames',{'bin','referenceLeft_m','referenceRight_m','direction','samples'});
opt = struct('mode',"standard",'binIndex',binIndex, ...
    'rawWindow',5,'acquisitionBudget',30);
replayTrials = 5;
assert(mod(opt.acquisitionBudget,2)==0 && opt.acquisitionBudget>=2, ...
    'NikonMotor:PairedAcquisitionBudget', ...
    'Use an even acquisition budget so every identical-FF pair is complete.');
methods = ["standard","raw_rcs","pair_mean","pair_confidence"];
orderSeed = 8; rng(orderSeed,'twister');
methods = methods(randperm(numel(methods)));
confirmEachTrial = false;
velocitySweepEnabled = false;

%% 3. モデル・周期・固定バッファを変更したときだけビルドする
rebuildTarget = false;
if rebuildTarget, run(fullfile(projectRoot,"exp03_FF","setup_tunable.m")); end

%% 4. 各手法を30回学習し、最後の候補FFを固定して5回実機評価する
load_system(fullfile(projectRoot,ModelName));
blockDir = create_run_directory(fullfile(projectRoot,"data","ilc"), ...
    "exp08_paired_confidence");
manifest = struct('methods',methods,'orderSeed',orderSeed,'Ts',Ts,'opt',opt, ...
    'replayTrials',replayTrials,'traj',traj,'Kd',Kd,'Gn0',Gn0,'Q',Q,'Fc',Fc, ...
    'plantPath',plantPath,'dist',dist,'v_max',v_max,'a_max',a_max, ...
    'startCount',startCount,'activeMask',activeMask,'binTable',binTable, ...
    'positionBinWidth',positionBinWidth,'minAbsVelocity',minAbsVelocity, ...
    'alphaClock',"physical_pair_closing_acquisition");
save_experiment_result(blockDir,"manifest",manifest);
results = struct('method',{},'trainFile',{},'replayFile',{});
for methodIndex = 1:numel(methods)
    method = methods(methodIndex);
    fprintf("\nMethod %d/%d: %s\n",methodIndex,numel(methods),method);
    methodOpt = opt; methodOpt.mode = method;
    [~,homing] = home_to_start(startCount);
    pre = read_tunable_idle_state(Ts);
    Ntrial = opt.acquisitionBudget;
    ilcRunDir = create_run_directory(blockDir,method+"_train");
    ilcExtension = struct('initialFeedforward',zeros(N,1), ...
        'update',@(f,e,k,base,state)exp08_update( ...
        f,e,k,base,state,ops,methodOpt));
    trainingClock = tic;
    run(fullfile(projectRoot,"exp04_ILC","obtainMeasurement.m"));
    elapsedSeconds = toc(trainingClock);
    post = read_tunable_idle_state(Ts);
    assert_logged_feedforward(history,completedTrials);
    saturatedSamples = sum(abs(history.u(:,1:completedTrials))>=MAX_INPUT-1e-6,'all');
    training = struct('history',history,'completedTrials',completedTrials, ...
        'method',method,'Ts',Ts,'elapsedSeconds',elapsedSeconds,'opt',methodOpt, ...
        'homing',homing,'pre',pre,'post',post,'saturatedSamples',saturatedSamples);
    trainFile = finalize_experiment_result(ilcRunDir,"training",training, ...
        fullfile('raw','single'),"ilc_progress_single.mat");
    assert(completedTrials==Ntrial,'NikonMotor:IncompletePairedILC', ...
        'Training stopped; partial data: %s',trainFile);
    frozenFF = history.updateInfo{completedTrials}.nextFF;
    assert(numel(frozenFF)==N && all(isfinite(frozenFF)), ...
        'NikonMotor:FinalCandidateUnavailable', ...
        'The final unapplied candidate is unavailable.');

    [~,homing] = home_to_start(startCount);
    pre = read_tunable_idle_state(Ts);
    Ntrial = replayTrials;
    ilcRunDir = create_run_directory(blockDir,method+"_replay");
    holdOpt = opt; holdOpt.mode = "hold";
    ilcExtension = struct('initialFeedforward',frozenFF, ...
        'update',@(f,e,k,base,state)exp08_update(f,e,k,base,state,ops,holdOpt));
    replayClock = tic;
    run(fullfile(projectRoot,"exp04_ILC","obtainMeasurement.m"));
    elapsedSeconds = toc(replayClock);
    post = read_tunable_idle_state(Ts);
    assert_logged_feedforward(history,completedTrials);
    assert(max(abs(history.f(:,1:completedTrials)-frozenFF),[],'all')<1e-12, ...
        'NikonMotor:FrozenFFChanged','Frozen replay changed the submitted feedforward.');
    saturatedSamples = sum(abs(history.u(:,1:completedTrials))>=MAX_INPUT-1e-6,'all');
    replay = struct('history',history,'completedTrials',completedTrials, ...
        'method',method,'Ts',Ts,'frozenFF',frozenFF, ...
        'elapsedSeconds',elapsedSeconds,'firstAppliedHere',true, ...
        'homing',homing,'pre',pre,'post',post,'saturatedSamples',saturatedSamples);
    replayFile = finalize_experiment_result(ilcRunDir,"replay",replay, ...
        fullfile('raw','single'),"ilc_progress_single.mat");
    assert(completedTrials==Ntrial,'NikonMotor:IncompletePairedILC', ...
        'Replay stopped; partial data: %s',replayFile);
    assert(saturatedSamples==0,'NikonMotor:CurrentSaturated', ...
        'Frozen replay saturated; inspect %s before comparing methods.',replayFile);
    results(methodIndex) = struct('method',method, ... %#ok<SAGROW>
        'trainFile',string(trainFile),'replayFile',string(replayFile));
    save_experiment_result(blockDir,"block",struct('manifestFile', ...
        string(fullfile(blockDir,'manifest.mat')),'results',results));
end
clear ilcExtension
%% 5. 学習曲線・固定FFの再現性・ペアの信頼度を描画し、保存する
summaryTable = exp08_report(results,manifest,blockDir);
disp(summaryTable);

function assert_logged_feedforward(history,completedTrials)
submitted = history.f(:,1:completedTrials);
expected = [zeros(1,completedTrials);submitted(1:end-1,:)];
assert(max(abs(history.ff(:,1:completedTrials)-expected),[],'all')<1e-7, ...
    'NikonMotor:CaptureMismatch', ...
    'Recorded feedforward differs from the submitted paired-ILC waveform.');
end
