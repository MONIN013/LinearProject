%[text] # Demo 6: Allocation Transfer Experiment
%[text] 2軸への電流配分を変え、exp05の位置・速度・加速度FFが別の配分でも使えるか比較する。
%[text] **実機が動く節は3と5。** 節1・2は準備、節4は保存した教師からの同定。全体実行でHomingから保存まで進む。
%[text] ## 1. Load settings and design the feedback controller
clear; close all;
projectRoot = setup_project();
run(fullfile(projectRoot,"config","config_tunable.m"));
load(fullfile(projectRoot,"config","data","pana_params.mat"));
[plant,plantPath] = load_experiment_plant(projectRoot,plantDataFile,Ts);
Pd = plant.Pd; Jn = plant.Jn; Dn = plant.Dn; Ndelay = plant.Ndelay;
[~,Gn0] = modelCreate(struct('m',Jn,'d',Dn,'k',0,'delay',Ndelay, ...
    'lp',[0,0,0]),Ts,Pd.Frequency);
[fb,~,~] = fbDesign(Pd,Ts);
Kd = fb.K;
feedbackFlag = 1;
S = feedback(1,Pd*Kd);
sensitivityPeak = max(abs(squeeze(freqresp(S))));
assert(Ts==1/4000,'NikonMotor:AllocationPeriod','Exp06 uses the 4 kHz target.');
assert(isstable(feedback(Gn0.modelDelayed*Kd,1)) && sensitivityPeak<2, ...
    'NikonMotor:AllocationFeedback','Check nominal stability and measured sensitivity.');
fprintf('Nominal feedback: stable, sensitivity %.4f < 2; plant %s\n',sensitivityPeak,plantPath);
%[text] これは既存配分で同定したプラントの確認。配分変更後の安定性・感度は実測前には確定しない。

%%
%[text] ## 2. Prepare the allocation and trajectories
%[text] 軸1・2の重なり区間で60 mm往復。w1=1+beta、w2=1-beta*ratio。ratioは推力定数g1/g2で、初期値1は仮定。
%[text] 学習9条件、validation 3条件、test 3条件。各配分の3軌道から4係数を求め、beta方向に線形補間する。
dist = .06;
startCount = 56100000;
pair = 1;
forceRatio = 1;
overlapCounts = [55809159,57600015;59369714,61230980;63068811,64809681];
trackingLimit = 3e-3;
terminalLimit = 100e-6;
endCount = startCount+dist/ENCODER_RESOLUTION;
assert(startCount-(trackingLimit+terminalLimit)/ENCODER_RESOLUTION>overlapCounts(pair,1) && ...
    endCount+(trackingLimit+terminalLimit)/ENCODER_RESOLUTION<overlapCounts(pair,2), ...
    'NikonMotor:AllocationRange','Keep the whole trajectory inside the selected pair overlap.');
plan = make_allocation_plan();
profiles = cell(height(plan),1);
figure; tiledlayout(3,1);
for caseIndex = 1:height(plan)
    allocation_weights(plan.beta(caseIndex),forceRatio);
    traj = generate_allocation_profile(dist,plan.duration(caseIndex),plan.skew(caseIndex),Ts);
    profiles{caseIndex} = traj;
    prepare_tunable_trajectory_parameters(traj.pos,zeros(size(traj.pos)),tunable_trajectory_buffer_capacity());
    % Per-axis data is recorded by the same File Writer as the trajectory.
    if mod(caseIndex,3)==1 || caseIndex==11 || caseIndex==14
        nexttile(1); plot(traj.time,traj.pos); hold on; ylabel('Position [m]'); grid on;
        nexttile(2); plot(traj.time,traj.vel); hold on; ylabel('Velocity [m/s]'); grid on;
        nexttile(3); plot(traj.time,traj.acc); hold on; ylabel('Acceleration [m/s^2]'); grid on;
    end
end
xlabel('Time [s]');
disp(plan);

Ntrial = 80;
reuseSavedTeachers = true;
teacherDataFile = fullfile(projectRoot,'data','allocation_transfer','current_teachers.mat');
Fc = 420;
[Qz,Qp,Qgain] = butter(4,Fc/(1/(2*Ts)));
[Qsos,Qscale] = zp2sos(Qz,Qp,Qgain);
teacherOptions = struct('minTrials',5,'window',3,'averagingWindow',8, ...
    'validationTrials',8,'errorRelativeChange',.05,'ffRelativeChange',.05, ...
    'requireRmsPlateau',false, ... % Accept every fixed repeat by absolute accuracy.
    'feedbackRatio',.20,'trackingLimit',trackingLimit,'terminalLimit',terminalLimit, ...
    'maxInput',MAX_INPUT,'endPosition',overlapCounts(pair,2)*ENCODER_RESOLUTION);
predictionMarginList = repmat(.15,1,9);
% Acceptance targets for this short stroke, not previously measured accuracy.
teacherAccuracyLimits = repmat(1e-6*[10,10,100],9,1); % whole RMS, moving RMS, peak
derivativeWindow = 81;
currentOffsetSamples = -Ndelay;
xGrid = startCount*ENCODER_RESOLUTION+(.0005:.0005:dist-.0005)';
blendDistance = .0005;
ffGains = zeros(4,1);
mapGain = 1;
% The Simulink model, cycle and buffers are unchanged. Deploy the new
% MotorRuntime once before section 3; there is no automatic Activate here.

%%
%[text] ## 3. Collect the converged ILC teachers
%[text] **実機動作:** 9条件でexp04のILCを行う。各試行の直前に配分を設定し、サーボOFFで通常配分へ戻す。Homingは通常配分で行う。
%[text] 最後の固定8回を教師に使う。教師の精度判定・Q420 Hz・電流上限・停止確認はexp05と共通。
if reuseSavedTeachers && isfile(teacherDataFile)
    saved = load(teacherDataFile,'trainingFiles');
    trainingFiles = saved.trainingFiles;
    assert(numel(trainingFiles)==9 && all(isfile(trainingFiles)), ...
        'NikonMotor:MissingTeacherData','Nine allocation teachers are required.');
else
    experimentRunDir = create_run_directory('data/allocation_transfer','training');
    trainingFiles = strings(0,1);
    for caseIndex = 1:9
        profileIndex = caseIndex;
        traj = profiles{caseIndex}; r = traj.pos; f = zeros(size(r));
        allocationSettings = struct('pair',pair,'beta',plan.beta(caseIndex),'ratio',forceRatio);
        teacherOptions.allocation = allocationSettings;
        method = "ilc_teacher";
        runTag = sprintf('case_%02d_ilc_teacher',caseIndex);
        [~,homing] = home_to_start(startCount);
        run(fullfile(projectRoot,'exp05_AccelerationFF','obtainMeasurement.m'));
        trainingFiles(end+1,1) = string(resultFile); %#ok<SAGROW>
        save_experiment_result(experimentRunDir,'training_progress', ...
            struct('trainingFiles',trainingFiles,'plan',plan,'pair',pair,'forceRatio',forceRatio));
    end
end

%%
%[text] ## 4. Fit the allocation-dependent maps
%[text] **実機動作なし:** 適用FF（row7）と実測位置（row8）からexp05と同じ4係数を同定。配分ごとに3形状を使い、反復を独立形状に数えない。
%[text] 保存済み教師の設定・固定FFの精度・軸別ログの合格を再確認する。validation/testは同定に使わない。
betas = [-.1,0,.1];
maps = cell(size(betas));
for mapIndex = 1:numel(betas)
    cases = find(plan.split=="train" & plan.beta==betas(mapIndex));
    training = cell(numel(cases)*teacherOptions.validationTrials,1);
    for teacherIndex = 1:numel(cases)
        caseIndex = cases(teacherIndex);
        data = load(trainingFiles(caseIndex));
        expectedAllocation = struct('pair',pair,'beta',plan.beta(caseIndex),'ratio',forceRatio);
        assert(data.passed && isequal(data.allocation,expectedAllocation) && ...
            data.profileIndex==caseIndex && data.Ts==Ts && data.Ndelay==Ndelay && data.Fc==Fc && ...
            isequal(data.Kd,Kd) && strcmp(data.plantPath,plantPath) && ...
            isequal(data.Qsos,Qsos) && isequal(data.Qscale,Qscale) && ...
            abs(data.homing.final_count-startCount)<=1000 && ...
            isequal(data.traj.pos,profiles{caseIndex}.pos) && isequal(data.traj.vel,profiles{caseIndex}.vel), ...
            'NikonMotor:TrainingSettingsMismatch','Saved teacher differs from the configured experiment.');
        settings = teacherOptions;
        settings.rmsLimit = teacherAccuracyLimits(caseIndex,1);
        settings.movingRmsLimit = teacherAccuracyLimits(caseIndex,2);
        settings.peakErrorLimit = teacherAccuracyLimits(caseIndex,3);
        checked = evaluate_ilc_teacher(data.history,data.completedTrials,data.traj.vel,settings);
        assert(checked.converged && checked.accuracyPassed,'NikonMotor:TrainingAccuracyFailed', ...
            'Saved teacher %d does not meet the configured accuracy targets.',caseIndex);
        ix = data.completedTrials-teacherOptions.validationTrials+1:data.completedTrials;
        for repeatIndex = 1:numel(ix)
            if isfield(data.history,'allocationLog')
                axisRecord = data.history.allocationLog{ix(repeatIndex)};
            else
                axisRecord = load(data.history.allocationLogFiles{ix(repeatIndex)}, ...
                    'passed','allocation','Ts');
            end
            assert(axisRecord.passed && isequal(axisRecord.allocation,expectedAllocation) && axisRecord.Ts==Ts, ...
                'NikonMotor:AllocationTeacherLog','Missing or mismatched successful axis log.');
            training{(teacherIndex-1)*numel(ix)+repeatIndex} = struct('passed',data.passed, ...
                'method',data.method,'profileIndex',caseIndex,'teacher',checked,'Ts',Ts, ...
                'y_absolute_ex',data.history.y_absolute(:,ix(repeatIndex)), ...
                'ff_ex',data.history.ff(:,ix(repeatIndex)), ...
                'count_ex',data.history.count(:,ix(repeatIndex)), ...
                'r_ex',data.history.r(:,ix(repeatIndex)));
        end
        clear data
    end
    maps{mapIndex} = fit_acceleration_ff(training,xGrid,derivativeWindow,currentOffsetSamples);
    assert(all(maps{mapIndex}.valid),'NikonMotor:InvalidAllocationMap','Some positions are not identifiable.');
end
save(teacherDataFile,'trainingFiles');
mapRunDir = create_run_directory('data/allocation_transfer','map');
mapFile = save_experiment_result(mapRunDir,'allocation_map', ...
    struct('maps',{maps},'betas',betas,'pair',pair,'forceRatio',forceRatio, ...
    'trainingFiles',trainingFiles,'plan',plan,'Ts',Ts,'Kd',Kd,'plantPath',plantPath,'Ndelay',Ndelay));
figure; tiledlayout(4,1);
units = ["g [A]","b [A s/m]","c [A]","alpha [A s^2/m]"];
for coefficient = 1:4
    nexttile;
    for mapIndex = 1:numel(betas)
        plot(maps{mapIndex}.x,maps{mapIndex}.coefficients(:,coefficient), ...
            'DisplayName',sprintf('beta=%+.2f',betas(mapIndex))); hold on;
    end
    ylabel(units(coefficient)); grid on; legend;
end
xlabel('Absolute position [m]');
save_experiment_figures(mapRunDir,gcf);

%%
%[text] ## 5. Compare fixed and transferred FF
%[text] **実機動作:** FFなし、beta=0の固定マップ、実際のbetaへ補間したマップを比較する。ここでは再学習しない。
%[text] beta=0では固定と補間が同じなので重複取得を省く。validation/testの誤差は別々に残す。
experimentRunDir = create_run_directory('data/allocation_transfer','comparison');
save_experiment_result(experimentRunDir,'comparison_settings', ...
    struct('mapFile',mapFile,'plan',plan,'pair',pair,'forceRatio',forceRatio, ...
    'blendDistance',blendDistance,'Ts',Ts,'Kd',Kd,'Ndelay',Ndelay));
comparison = table();
fixedMap = interpolate_allocation_map(maps,betas,0);
for caseIndex = 10:height(plan)
    profileIndex = caseIndex;
    traj = profiles{caseIndex}; r = traj.pos;
    allocationSettings = struct('pair',pair,'beta',plan.beta(caseIndex),'ratio',forceRatio);
    transferredMap = interpolate_allocation_map(maps,betas,allocationSettings.beta);
    methods = ["allocation_fb","allocation_fixed","allocation_transfer"];
    if allocationSettings.beta==0, methods = methods(1:2); end
    comparisonFigure = figure; tiledlayout(3,1);
    for method = methods
        [~,homing] = home_to_start(startCount);
        f = zeros(size(r));
        if method~="allocation_fb"
            ffMap = fixedMap;
            if method=="allocation_transfer", ffMap = transferredMap; end
            origin = homing.final_count*ENCODER_RESOLUTION;
            edge = ffMap.coefficients([1,end],:);
            edgeIndex = 1+double(origin+traj.pos>mean(ffMap.x([1,end])));
            baseline = sum(edge(edgeIndex,:).*[ones(size(r)),traj.vel,sign(traj.vel),traj.acc],2);
            w = min(max((abs(traj.vel)-.002)/.002,0),1);
            baseline = baseline.*w.^2.*(3-2*w);
            f = acceleration_feedforward(ffMap,traj,origin,baseline,mapGain,blendDistance);
        end
        f = [f(1+Ndelay:end);repmat(f(end),Ndelay,1)];
        runTag = sprintf('case_%02d_%s',caseIndex,method);
        run(fullfile(projectRoot,'exp05_AccelerationFF','obtainMeasurement.m'));
        moving = abs([0;traj.vel(1:end-1)])>.002;
        accelerating = abs([0;traj.acc(1:end-1)])>.002;
        comparison = [comparison;table(caseIndex,plan.split(caseIndex),plan.beta(caseIndex), ...
            method,trialResult.rmsError,sqrt(mean(e_ex(moving).^2)), ...
            sqrt(mean(e_ex(accelerating).^2)),trialResult.peakError,max(abs(u_ex)),string(resultFile), ...
            'VariableNames',{'condition','split','beta','method','rmsError','rmsMoving', ...
            'rmsAccelerating','peakError','peakCurrent','resultFile'})]; %#ok<AGROW>
        save_experiment_result(experimentRunDir,'comparison',struct('comparison',comparison,'mapFile',mapFile));
        figure(comparisonFigure);
        nexttile(1); plot(t_ex,e_ex,'DisplayName',method); hold on; ylabel('Error [m]'); grid on; legend;
        nexttile(2); plot(t_ex,ff_ex,'DisplayName',method); hold on; ylabel('FF [A]'); grid on;
        nexttile(3); plot(t_ex,u_ex,'DisplayName',method); hold on; ylabel('Total current [A]'); grid on;
        xlabel('Time [s]');
        save_experiment_figures(runDir,comparisonFigure);
    end
end
disp(comparison);
fprintf('ALLOCATION_CAPTURE_COMPLETE: %d teachers, %d comparisons.\n',numel(trainingFiles),height(comparison));
fprintf('Compare held-out errors to judge transfer performance: %s\n',experimentRunDir);
