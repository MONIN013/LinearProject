%% Capture a comparison trial or collect an ILC teacher using exp04
% Caller supplies r, f, traj, homing, method, profileIndex and runTag.
resumingTeacher = method=="ilc_teacher" && exist('teacherResumeFile','var') && ...
    strlength(teacherResumeFile)>0;
if resumingTeacher
    savedFF = load(teacherResumeFile,'f');
    f = savedFF.f(:);
    clear savedFF
end
prepare_tunable_trajectory_parameters(r, f, tunable_trajectory_buffer_capacity());
if method ~= "ilc_teacher"
    assert(max(abs(f))<2*MAX_INPUT, ...
        'NikonMotor:FFCurrentLimit', 'FF exceeds the 4 A waveform guard.');
end
load_system(fullfile(projectRoot, ModelName));
pre = read_tunable_idle_state(Ts);
assert(abs(pre.positionCount-homing.final_count)<=1000, ...
    'NikonMotor:StartPositionChanged', 'Stage position changed after Homing.');
runDir = create_run_directory(experimentRunDir, runTag);
trialResult = struct('method',method, 'profileIndex',profileIndex, ...
    'traj',traj, 'r',r, 'f',f, 'Ts',Ts, 'Kd',Kd, 'plantPath',plantPath, ...
    'Ndelay',Ndelay, 'MAX_INPUT',MAX_INPUT, 'homing',homing, 'pre',pre, ...
    'ffGains',ffGains, 'mapGain',mapGain, 'blendDistance',blendDistance, ...
    'trackingLimit',trackingLimit, 'terminalLimit',terminalLimit, 'passed',false);
if resumingTeacher, trialResult.resumeFile = string(teacherResumeFile); end
save_experiment_result(runDir, 'result', trialResult);
clear measurement
try
    if method == "ilc_teacher"
        t = traj.time; Tend = t(end); N = numel(r);
        velocitySweepEnabled = false;
        teacherSettings = teacherOptions;
        teacherSettings.currentMargin = predictionMarginList(profileIndex);
        teacherSettings.rmsLimit = teacherAccuracyLimits(profileIndex,1);
        teacherSettings.movingRmsLimit = teacherAccuracyLimits(profileIndex,2);
        teacherSettings.peakErrorLimit = teacherAccuracyLimits(profileIndex,3);
        teacherSettings.velocity = traj.vel;
        teacherSettings.startCount = homing.final_count;
        if resumingTeacher, teacherSettings.resumeFile = string(teacherResumeFile); end
        ilcRunDir = runDir;
        run(fullfile(projectRoot, "exp04_ILC", "obtainMeasurement.m"));
        trialResult.history = history;
        trialResult.teacher = history.teacher;
        trialResult.completedTrials = completedTrials;
        trialResult.Ntrial = Ntrial;
        trialResult.Fc = Fc;
        trialResult.Qsos = Qsos; trialResult.Qscale = Qscale;
        trialResult.currentOffsetSamples = currentOffsetSamples;
        % Save the final APPLIED waveform; the next candidate was never measured.
        f = history.f(:,completedTrials);
        trialResult.f = f;
        clear teacherSettings
    else
        measurement = capture_tunable_trajectory(ModelName, r, f, Ts, runDir);
    end
    trialResult.post = read_tunable_idle_state(Ts);
    assert(isequal(size(measurement),[10,numel(r)]) && all(isfinite(measurement),'all'), ...
        'NikonMotor:InvalidCapture', 'Expected a finite 10-by-N capture.');
    count_ex = measurement(1,:);
    t_ex = (count_ex(:)-count_ex(1))*Ts;
    e_ex = measurement(2,:); u_ex = measurement(3,:);
    v_ex = measurement(4,:); y_ex = measurement(5,:);
    ff_ex = measurement(7,:); y_absolute_ex = measurement(8,:);
    r_ex = measurement(9,:);
    assert(all(diff(count_ex)==1), 'NikonMotor:LostSamples', ...
        'Measurement contains missing or out-of-order samples.');
    % Reference/Delay2 delays logged reference and FF by one sample.
    assert(max(abs(r_ex'-[0;r(1:end-1)]))<1e-7 && ...
        max(abs(ff_ex'-[0;f(1:end-1)]))<1e-7, ...
        'NikonMotor:CaptureMismatch', 'Recorded reference/FF differs from this trial.');
    trialResult.count_ex = count_ex; trialResult.t_ex = t_ex;
    trialResult.e_ex = e_ex; trialResult.u_ex = u_ex;
    trialResult.v_ex = v_ex; trialResult.y_ex = y_ex;
    trialResult.ff_ex = ff_ex; trialResult.y_absolute_ex = y_absolute_ex;
    trialResult.r_ex = r_ex;
    trialResult.rmsError = sqrt(mean(e_ex.^2));
    trialResult.peakError = max(abs(e_ex));
    trialResult.saturatedSamples = sum(abs(u_ex)>=MAX_INPUT-1e-6);
    assert(trialResult.peakError<trackingLimit && abs(y_ex(end))<terminalLimit, ...
        'NikonMotor:TrackingFailed', 'Inspect tracking and terminal error before continuing.');
    assert(trialResult.saturatedSamples==0, 'NikonMotor:CurrentSaturated', ...
        'Final trial still saturates. Inspect the recorded error and current before selecting a teacher or comparing FF.');
    if method == "ilc_teacher"
        if trialResult.teacher.validationTrials>=teacherOptions.validationTrials
            assert(trialResult.teacher.accuracyPassed,'NikonMotor:TeacherAccuracyFailed', ...
                'Teacher accuracy failed: whole RMS %.2f/%.2f um, moving RMS %.2f/%.2f um, peak %.2f/%.2f um.', ...
                1e6*trialResult.teacher.accuracyRms,1e6*trialResult.teacher.settings.rmsLimit, ...
                1e6*trialResult.teacher.accuracyMovingRms,1e6*trialResult.teacher.settings.movingRmsLimit, ...
                1e6*trialResult.teacher.accuracyPeak,1e6*trialResult.teacher.settings.peakErrorLimit);
        end
        assert(trialResult.teacher.converged, 'NikonMotor:ILCTeacherNotConverged', ...
            'ILC did not converge within %d trials. Inspect teacher_progress before continuing.', Ntrial);
    end
    trialResult.passed = true;
catch cause
    clear teacherSettings
    trialResult.failure = cause.message;
    % Capture owns shutdown and raw archiving, including interruption. Preserve
    % the available evidence if subsequent decoding or idle verification fails.
    if exist('measurement','var'), trialResult.measurement = measurement; end
    if ~isfield(trialResult,'post')
        try
            trialResult.post = read_tunable_idle_state(Ts);
        catch stopCause
            trialResult.stopUnverified = stopCause.message;
        end
    end
    save_experiment_result(runDir, 'result', trialResult);
    rethrow(cause);
end
resultFile = save_experiment_result(runDir, 'result', trialResult);
fprintf('%s: RMS %.1f um, peak %.1f um, current %.3f A, idle verified\n', ...
    runTag, 1e6*trialResult.rmsError, 1e6*trialResult.peakError, max(abs(u_ex)));
