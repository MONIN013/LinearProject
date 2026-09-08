%% Run the ILC trials with one external-mode connection
[~, modelName] = fileparts(ModelName);
if exist("velocitySweepEnabled", "var") && velocitySweepEnabled
    sweep = run_ilc_velocity_sweep( ...
        string(modelName), v_max_list, dist, a_max, t_pause, t_pre, ...
        t_post, Ntrial, Ts, fb, Gn0, Qsos, Qscale, MAX_INPUT, ...
        confirmEachTrial, Kd, Q, Fc, plantPath, ilcRunDir);
    history = sweep.history;
    completedTrials = sweep.completedTrials;
    v_max = sweep.v_max;
    traj = sweep.traj;
    t = sweep.t;
    r = sweep.r;
    Tend = sweep.Tend;
    N = sweep.N;
    resultFiles = sweep.resultFiles;
    completedTrialsByVelocity = sweep.completedTrialsByVelocity;
    completedVelocities = sweep.completedVelocities;
elseif exist("teacherSettings", "var") && ~isempty(teacherSettings)
    teacherSettings.maxTrials = Ntrial;
    if isfield(teacherSettings,'resumeFile')
        resumeData = load(teacherSettings.resumeFile);
        teacherSettings.startCount = resumeData.teacher.settings.startCount;
        resumeRuntime = struct('Ts',Ts,'Fc',Fc,'Qsos',Qsos,'Qscale',Qscale, ...
            'Kd',Kd,'Ndelay',Ndelay,'plantPath',plantPath);
        [history,teacherSettings.firstTrial] = resume_ilc_teacher_history( ...
            resumeData,traj,Ntrial,teacherSettings,resumeRuntime);
        clear resumeData resumeRuntime
    else
        history = initialize_history(t, r, Ntrial);
    end
    [history, completedTrials, measurement] = run_ilc_trials( ...
        string(modelName), history, Ntrial, N, t, Tend, Ts, fb, Gn0, ...
        Qsos, Qscale, MAX_INPUT, false, ilcRunDir, "teacher", teacherSettings);
else
    history = initialize_history(t, r, Ntrial);
    [history, completedTrials] = run_ilc_trials( ...
        string(modelName), history, Ntrial, N, t, Tend, Ts, fb, Gn0, ...
        Qsos, Qscale, MAX_INPUT, confirmEachTrial, ilcRunDir, "single");
end

function [history, completedTrials, measurement] = run_ilc_trials( ...
        model, history, Ntrial, N, t, Tend, Ts, fb, Gn0, ...
        Qsos, Qscale, MAX_INPUT, confirmEachTrial, runDir, velocityTag, teacherSettings)
if nargin<16, teacherSettings = []; end
if ~isempty(teacherSettings)
    validateattributes(Ntrial, {'double'}, {'scalar','integer', ...
        '>=',max(teacherSettings.minTrials,teacherSettings.window+1)});
    assert(teacherSettings.maxInput==MAX_INPUT, ...
        'NikonMotor:TeacherCurrentLimit', 'Teacher current limit must match the active controller.');
    if isfield(teacherSettings,'averagingWindow')
        validateattributes(teacherSettings.averagingWindow,{'double'},{'scalar','integer','>=',2});
        validateattributes(teacherSettings.validationTrials,{'double'}, ...
            {'scalar','integer','>=',teacherSettings.window+1});
        assert(Ntrial>=max(2*teacherSettings.averagingWindow, ...
            teacherSettings.averagingWindow+teacherSettings.window)+teacherSettings.validationTrials, ...
            'NikonMotor:TeacherTrialsInsufficient','Allow enough trials for learning and fixed-FF validation.');
    end
end
[dataDir, bufferCapacity] = prepare_external_mode(model, N, Ts);
cleanupGuard = onCleanup(@()reset_disconnect_and_archive( ...
    model, N, bufferCapacity, dataDir, runDir, velocityTag, 0));
connect_external_mode(model);
[history, completedTrials, measurement] = run_ilc_trial_sequence( ...
    model, history, Ntrial, t, Tend, Ts, fb, Gn0, Qsos, Qscale, ...
    MAX_INPUT, confirmEachTrial, dataDir, bufferCapacity, runDir, velocityTag, teacherSettings);
end

function sweep = run_ilc_velocity_sweep( ...
        model, vMaxList, dist, aMax, tPause, tPre, tPost, Ntrial, ...
        Ts, fb, Gn0, Qsos, Qscale, maxInput, confirmEachTrial, ...
        Kd, Q, Fc, plantPath, runDir)
assert(~isempty(vMaxList), "The velocity sweep requires at least one speed.");
resultFiles = strings(numel(vMaxList), 1);
completedTrialsByVelocity = zeros(numel(vMaxList), 1);
completedVelocities = 0;

traj = generateMyProfile_TrajectTools( ...
    0.0, dist, vMaxList(1), aMax/2, Ts, tPause, tPre, tPost);
t = traj.time;
r = traj.pos(:);
Tend = t(end);
N = numel(r);

[dataDir, bufferCapacity] = prepare_external_mode(model, N, Ts);
cleanupGuard = onCleanup(@()reset_disconnect_and_archive( ...
    model, N, bufferCapacity, dataDir, runDir, "velocity_interrupted", 0));
connect_external_mode(model);

for velocityIndex = 1:numel(vMaxList)
    v_max = vMaxList(velocityIndex);
    fprintf("\nVelocity %d/%d: %.1f m/s\n", ...
        velocityIndex, numel(vMaxList), v_max);

    if velocityIndex > 1
        traj = generateMyProfile_TrajectTools( ...
            0.0, dist, v_max, aMax/2, Ts, tPause, tPre, tPost);
        t = traj.time;
        r = traj.pos(:);
        Tend = t(end);
        N = numel(r);
    end

    history = initialize_history(t, r, Ntrial);
    velocityTag = sprintf("velocity_%03d_V%.3f", velocityIndex, v_max);
    [history, completedTrials] = run_ilc_trial_sequence( ...
        model, history, Ntrial, t, Tend, Ts, fb, Gn0, Qsos, Qscale, ...
        maxInput, confirmEachTrial, dataDir, bufferCapacity, runDir, velocityTag);

    completedTrialsByVelocity(velocityIndex) = completedTrials;
    resultFiles(velocityIndex) = string(save_experiment_result( ...
        runDir, sprintf("ilc_result_V%.3f", v_max), struct( ...
        "history", history, "completedTrials", completedTrials, ...
        "v_max", v_max, "Kd", Kd, "traj", traj, "Q", Q, ...
        "Fc", Fc, "Ts", Ts, "plantPath", plantPath)));

    if completedTrials < Ntrial
        warning("NikonMotor:ILCVelocitySweepStopped", ...
            ["Velocity %.1f m/s completed only %d/%d trials. " ...
             "The velocity sweep has been stopped."], ...
            v_max, completedTrials, Ntrial);
        break
    end
    completedVelocities = velocityIndex;
end

sweep = struct( ...
    "history", history, ...
    "completedTrials", completedTrials, ...
    "v_max", v_max, ...
    "traj", traj, ...
    "t", t, ...
    "r", r, ...
    "Tend", Tend, ...
    "N", N, ...
    "resultFiles", resultFiles, ...
    "completedTrialsByVelocity", completedTrialsByVelocity, ...
    "completedVelocities", completedVelocities);
end

function history = initialize_history(t, r, Ntrial)
N = numel(r);
history = struct( ...
    "t", t, ...
    "reference", r(:), ...
    "count", zeros(N, Ntrial), ...
    "r", repmat(r, 1, Ntrial), ...
    "y", zeros(N, Ntrial), ...
    "e", zeros(N, Ntrial), ...
    "eNorm", nan(1, Ntrial), ...
    "f", zeros(N, Ntrial), ...
    "ff", zeros(N, Ntrial), ...
    "u", zeros(N, Ntrial), ...
    "y_absolute", zeros(N, Ntrial), ...
    "alpha", nan(1, Ntrial));
end

function [dataDir, bufferCapacity] = prepare_external_mode(model, N, Ts)
projectRoot = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(projectRoot, "simulink", "data");
assert_target_built(projectRoot, "tunable_build_info.mat", Ts);
set_param(model, "SimulationMode", "external", ...
    "ExtModeMexArgs", "'192.168.10.3.1.1' 0 16842784");
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(projectRoot, "Cache"), ...
    "CodeGenFolder", fullfile(projectRoot, "CodeGen"), "createDir", true);
bufferCapacity = get_buffer_capacity(model);
setvars(model, reset_values(N, bufferCapacity));
end

function connect_external_mode(model)
set_param(model, "SimulationCommand", "connect");
wait_until_connected(model, 10);
set_param(model, "SimulationCommand", "start");
pause(0.5);
end

function [history, completedTrials, measurement] = run_ilc_trial_sequence( ...
        model, history, Ntrial, t, Tend, Ts, fb, Gn0, ...
        Qsos, Qscale, MAX_INPUT, confirmEachTrial, dataDir, bufferCapacity, ...
        runDir, velocityTag, teacherSettings)
if nargin<17, teacherSettings = []; end
isTeacher = ~isempty(teacherSettings);
firstTrial = 1;
if isTeacher && isfield(teacherSettings,'firstTrial')
    firstTrial = teacherSettings.firstTrial;
    validateattributes(firstTrial,{'double'},{'scalar','integer','positive','<=',Ntrial});
end
completedTrials = firstTrial-1;
measurement = [];
progressFigure = gobjects(0);
try
for iteration = firstTrial:Ntrial
    r = history.r(:, iteration);
    f = history.f(:, iteration);
    if isTeacher
        history.pre{iteration} = read_tunable_idle_state(Ts);
        if iteration>1 && abs(history.pre{iteration}.positionCount-teacherSettings.startCount)>1000
            % Each capture rebases relative position. Correct accumulated return
            % drift with the existing absolute Homing, retaining the learned FF.
            history.rehoming{iteration} = struct('before',history.pre{iteration});
            reset_disconnect_and_archive(model,numel(r),bufferCapacity, ...
                dataDir,runDir,velocityTag,iteration-1);
            assert(string(get_param(model,'SimulationStatus'))=="stopped" && ...
                string(get_param(model,'ExtModeConnected'))=="off", ...
                'NikonMotor:HomingModelBusy', 'ILC must stop and disconnect before position correction.');
            read_tunable_idle_state(Ts);
            [~,history.rehoming{iteration}.homing] = home_to_start(teacherSettings.startCount);
            [dataDir,bufferCapacity] = prepare_external_mode(model,numel(r),Ts);
            connect_external_mode(model);
            history.pre{iteration} = read_tunable_idle_state(Ts);
            history.rehoming{iteration}.after = history.pre{iteration};
        end
        assert(abs(history.pre{iteration}.positionCount-teacherSettings.startCount)<=1000, ...
            'NikonMotor:StartPositionChanged', 'ILC starting position changed; sequence stopped.');
    end
    measurement = capture_trial( ...
        model, r, f, Tend, dataDir, Ts, bufferCapacity, runDir, ...
        velocityTag, iteration);

    assert(isequal(size(measurement),[10,numel(r)]) && ...
        all(isfinite(measurement),'all'), ...
        'NikonMotor:InvalidCapture', 'Expected a finite 10-by-N capture.');
    count = measurement(1, :);
    history.count(:, iteration) = count.';
    history.e(:, iteration) = measurement(2, :).';
    history.u(:, iteration) = measurement(3, :).';
    history.ff(:, iteration) = measurement(7, :).';
    history.y(:, iteration) = measurement(5, :).';
    history.y_absolute(:, iteration) = measurement(8, :).';
    history.r(:, iteration) = measurement(9, :).';
    history.eNorm(iteration) = norm(history.e(:, iteration), 2);
    save_experiment_result(runDir, ...
        sprintf("ilc_progress_%s", velocityTag), struct( ...
        "history", history, "completedTrials", completedTrials, ...
        "capturedTrials", iteration, "Ts", Ts));

    lostPackages = setdiff(count(1):count(end), count);
    fprintf("Trial %d/%d: ||e||_2 = %.6g, lost packages = %d\n", ...
        iteration, Ntrial, history.eNorm(iteration), numel(lostPackages));
    assert(isempty(lostPackages) && all(diff(count) == 1), ...
        "Measurement contains missing or out-of-order samples.");

    if isTeacher
        history.post{iteration} = read_tunable_idle_state(Ts);
        history.teacher = evaluate_ilc_teacher( ...
            history, iteration, teacherSettings.velocity, teacherSettings);
        completedTrials = iteration;
        save_experiment_result(runDir, "teacher_progress", struct( ...
            "history", history, "completedTrials", completedTrials, "Ts", Ts));
        fprintf("Teacher %d/%d: RMS %.1f um, FF change %.3g, FB/FF %.3g, saturated %d samples\n", ...
            iteration, Ntrial, 1e6*history.teacher.errorRms(end), ...
            history.teacher.ffRelativeChange(end), history.teacher.feedbackRatio(end), ...
            history.teacher.saturatedSamples(end));
        if history.teacher.converged || iteration==Ntrial
            progressFigure = plot_progress(progressFigure,t,history,iteration,f,f);
            break
        end
    end

    alpha = max(0.9^iteration, 0.3);
    history.alpha(iteration) = alpha;
    meanErrorUpdate = isTeacher && history.teacher.meanUpdateReady;
    if isTeacher && isfield(history,'validationStart') && ...
            history.validationStart>0 && ...
            any(history.teacher.saturatedSamples(history.validationStart:iteration)>0)
        history.validationStart = 0;
        history.learningStart = iteration+1;
        history.teacher.validationReady = false;
        fprintf('Fixed FF saturated; resuming ILC from trial %d.\n',iteration+1);
    end
    if meanErrorUpdate
        ix = iteration-teacherSettings.validationTrials+1:iteration;
        averaged = struct('t',t,'e',mean(history.e(:,ix),2), ...
            'u',mean(history.u(:,ix),2),'f',mean(history.f(:,ix),2), ...
            'teacher',history.teacher);
        % Suppress error corrections near rest, where mean-error updates worsened
        % the measured response. All samples remain in the accuracy checks.
        learningWeight = min(max((abs(teacherSettings.velocity)-.02)/.08,0),1);
        learningWeight = learningWeight.^2.*(3-2*learningWeight);
        [fNext,history.constrainedUpdate{iteration}] = update_ilc_constrained( ...
            averaged,1,Gn0,fb,Qsos,Qscale,MAX_INPUT,.6,learningWeight);
        history.meanErrorTrials{iteration} = ix;
        history.alpha(iteration) = history.constrainedUpdate{iteration}.rate;
        history.validationStart = iteration+1;
        history.validationStarts(end+1) = iteration+1;
        fprintf('Mean-error ILC update from trials %d to %d; fixed validation starts at %d.\n', ...
            ix(1),ix(end),iteration+1);
    elseif isTeacher && isfield(history,'validationStart') && history.validationStart>0
        history.alpha(iteration) = 0;
        fNext = history.validationFF;
    elseif isTeacher && history.teacher.validationReady
        history.alpha(iteration) = 0;
        w = teacherSettings.averagingWindow;
        history.validationFF = mean(history.f(:,iteration-w+1:iteration),2);
        history.validationStart = iteration+1;
        if ~isfield(history,'validationStarts'), history.validationStarts = []; end
        history.validationStarts(end+1) = history.validationStart;
        fNext = history.validationFF;
        fprintf('Fixed FF validation begins at trial %d, averaging trials %d to %d.\n', ...
            iteration+1,iteration-w+1,iteration);
    elseif isTeacher && any(history.teacher.saturatedSamples)
        % Once clipping occurs, retain a current-constrained update for this
        % sequence so unconstrained learning cannot reintroduce the excess.
        [fNext, history.constrainedUpdate{iteration}] = update_ilc_constrained( ...
            history,iteration,Gn0,fb,Qsos,Qscale,MAX_INPUT);
    else
        learningCorrection = lsimFB(fb, history.e(:, iteration), t) ...
            + lsimInvModel(Gn0, history.e(:, iteration));
        fNext = filtfilt_clean(Qsos, Qscale, f + alpha*learningCorrection);
    end

    padding = round(0.025/Ts); % preserve the original 25 ms edge padding
    assert(numel(fNext) > 2*padding, ...
        "The ILC trajectory is too short for the edge padding.");
    fNext(1:padding) = fNext(padding+1);
    fNext(end-padding+1:end) = fNext(end-padding);
    if meanErrorUpdate, history.validationFF = fNext; end
    completedTrials = iteration;

    progressFigure = plot_progress( ...
        progressFigure, t, history, iteration, f, fNext);

    if max(abs(fNext)) > 2*MAX_INPUT
        warning("NikonMotor:ILCInputLimit", ...
            "The next learned input exceeds 2*MAX_INPUT. Trials stopped.");
        break
    end
    if iteration < Ntrial
        history.f(:, iteration+1) = fNext;
    end
    if confirmEachTrial && iteration < Ntrial
        choice = questdlg( ...
            "Move to the next trial?", "ILC result check", ...
            "yes", "no", "no");
        if ~strcmp(choice, "yes"), break; end
    end
end
catch cause
    if isTeacher
        save_experiment_result(runDir, "teacher_failed", struct( ...
            "history", history, "completedTrials", completedTrials, ...
            "measurement", measurement, "failure", cause.message, ...
            "failureId", cause.identifier, "Ts", Ts));
    end
    rethrow(cause);
end
if isTeacher && isgraphics(progressFigure)
    save_experiment_figures(runDir,progressFigure);
end
end

function measurement = capture_trial( ...
        model, r, f, Tend, dataDir, Ts, bufferCapacity, runDir, ...
        velocityTag, iteration)
archive_measurement_parts(dataDir, runDir, ...
    fullfile("raw", velocityTag, sprintf("before_trial_%03d", iteration)));
try

runValues = prepare_tunable_trajectory_parameters(r, f, bufferCapacity);
runValues.p_active = 0;
runValues.p_servo = 0;
setvars(model, runValues);
setvars(model, struct("p_servo", 1));
servoSettlingTime = 1;
pause(servoSettlingTime);
setvars(model, struct("p_active", 1));
pause(Tend + 1);

setvars(model, struct("p_active", 0, "p_servo", 0));
wait_for_measurement_file(dataDir, 10);

[measurement, ~, ~, ~, metadata] = ...
    load_latest_twincat_measurement(dataDir, Ts);
if isempty(measurement)
    error("NikonMotor:MeasurementNotFound", ...
        "The ILC trial completed without a measurement file.");
end
if metadata.schema_name ~= "feedforward_v1"
    error("NikonMotor:UnexpectedMeasurementSchema", ...
        "Expected feedforward_v1 measurement data, but loaded %s.", ...
        metadata.schema_name);
end
if metadata.timestamp_source ~= "tc_yout.logical_time"
    error("NikonMotor:MeasurementTimestampMissing", ...
        "TwinCAT logical timestamps are required for an experiment capture.");
end
archive_measurement_parts(dataDir, runDir, ...
    fullfile("raw", velocityTag, sprintf("trial_%03d", iteration)));
catch cause
    reset_disconnect_and_archive( ...
        model, numel(r), bufferCapacity, dataDir, runDir, velocityTag, iteration);
    rethrow(cause);
end
end

function wait_for_measurement_file(dataDir, timeout)
pattern = fullfile(dataDir, "measurement_part*.mat");
t0 = tic;
while toc(t0) < timeout
    parts = dir(pattern);
    if any([parts.bytes] > 0)
        return
    end
    pause(0.05);
end
error("NikonMotor:MeasurementTimeout", ...
    "No closed measurement file appeared within %.1f seconds.", timeout);
end

function figureHandle = plot_progress( ...
        figureHandle, t, history, iteration, f, fNext)
if isempty(figureHandle) || ~isgraphics(figureHandle, "figure")
    figureHandle = figure( ...
        "Name", "ILC trial progress", ...
        "NumberTitle", "off", ...
        "WindowStyle", "normal");
else
    figure(figureHandle);
    clf(figureHandle);
end

tiledlayout(figureHandle, 4, 1);
nexttile; plot(t, history.e(:, iteration)); grid on;
ylabel("Error [m]"); title(sprintf("Trial %d", iteration));
nexttile; plot(t, f, t, fNext, "--"); grid on;
ylabel("Feedforward [A]"); legend("Current", "Next");
nexttile; plot(t, history.u(:, iteration)-history.ff(:, iteration)); grid on;
ylabel("Feedback [A]");
nexttile; semilogy(0:iteration-1, history.eNorm(1:iteration), "-o");
grid on; xlabel("Iteration"); ylabel("||e||_2");
drawnow;
end

function values = reset_values(N, bufferCapacity)
values = prepare_tunable_trajectory_parameters( ...
    zeros(N, 1), zeros(N, 1), bufferCapacity);
values.p_active = 0;
values.p_servo = 0;
end

function capacity = get_buffer_capacity(model)
mdlWks = get_param(model, "ModelWorkspace");
required = ["p_ref", "p_ff", "p_count"];
if any(arrayfun(@(name)~mdlWks.hasVariable(name), required))
    error("NikonMotor:TunableModelRebuildRequired", ...
        ["The model does not contain the fixed trajectory buffer. " ...
         "Run setup_tunable once, then future reference/FF changes " ...
         "will not require a build."]);
end

referenceParameter = mdlWks.evalin("p_ref");
feedforwardParameter = mdlWks.evalin("p_ff");
if ~isa(referenceParameter, "Simulink.Parameter") || ...
        ~isa(feedforwardParameter, "Simulink.Parameter")
    error("NikonMotor:TunableModelRebuildRequired", ...
        "p_ref and p_ff must be Simulink.Parameter objects. Rebuild once.");
end
capacity = numel(referenceParameter.Value);
if numel(feedforwardParameter.Value) ~= capacity
    error("NikonMotor:TunableBufferMismatch", ...
        "The reference and feedforward target buffers have different sizes.");
end
end

function setvars(model, values)
mdlWks = get_param(model, "ModelWorkspace");
names = fieldnames(values);
for k = 1:numel(names)
    name = names{k};
    value = values.(name);
    if ~isscalar(value), value = value(:); end
    if mdlWks.hasVariable(name)
        parameter = mdlWks.evalin(name);
        if isa(parameter, "Simulink.Parameter")
            parameter.Value = value;
        else
            parameter = Simulink.Parameter(value);
        end
    else
        parameter = Simulink.Parameter(value);
    end
    assignin(mdlWks, name, parameter);
end
set_param(model, "SimulationCommand", "update");
end

function wait_until_stopped(model, timeout)
t0 = tic;
while toc(t0) < timeout
    if string(get_param(model, "SimulationStatus")) == "stopped"
        return
    end
    pause(0.05);
end
error("NikonMotor:ExternalModeTimeout", ...
    "The model did not stop within %.1f seconds.", timeout);
end

function wait_until_connected(model, timeout)
t0 = tic;
while toc(t0) < timeout
    if string(get_param(model, "ExtModeConnected")) == "on"
        return
    end
    pause(0.05);
end
error("NikonMotor:ExternalModeTimeout", ...
    "The model did not connect within %.1f seconds.", timeout);
end

function reset_and_disconnect(model, N, bufferCapacity)
try
    setvars(model, struct("p_active", 0, "p_servo", 0));
catch cause
    warning("NikonMotor:ResetFailed", ...
        "ILC safety reset failed: %s", cause.message);
end

try
    status = string(get_param(model, "SimulationStatus"));
    if any(status == ["running", "external", "paused", "initializing"])
        set_param(model, "SimulationCommand", "stop");
        wait_until_stopped(model, 5);
    end
catch cause
    warning("NikonMotor:StopFailed", ...
        "ILC stop failed: %s", cause.message);
end
try
    setvars(model, reset_values(N, bufferCapacity));
catch cause
    warning("NikonMotor:ResetFailed", ...
        "ILC trajectory reset failed: %s", cause.message);
end
try
    set_param(model, "SimulationCommand", "disconnect");
catch cause
    warning("NikonMotor:DisconnectFailed", ...
        "External-mode disconnect failed: %s", cause.message);
end
end

function reset_disconnect_and_archive( ...
        model, N, bufferCapacity, dataDir, runDir, velocityTag, iteration)
reset_and_disconnect(model, N, bufferCapacity);
try
    archive_measurement_parts(dataDir, runDir, ...
        fullfile("raw", velocityTag, sprintf("trial_%03d", iteration)));
catch cause
    warning("NikonMotor:MeasurementArchiveFailed", ...
        "ILC raw measurement was left in staging: %s", cause.message);
end
end
