function [measurement, runDir, metadata] = capture_tunable_trajectory(ModelName, r, f, Ts, runDir, allocationRequestId)
%CAPTURE_TUNABLE_TRAJECTORY Run one trajectory using the deployed tunable model.
% The caller prepares controller parameters. Raw parts are retained in runDir/raw.
if nargin < 5 || isempty(runDir)
    runDir = create_run_directory('data/ff','trajectory');
end
if nargin < 6, allocationRequestId = uint32(0); end
validateattributes(allocationRequestId,{'uint32'},{'scalar'});
[~, model] = fileparts(ModelName);
model = string(model);
projectRoot = fileparts(fileparts(mfilename("fullpath")));
load_system(fullfile(projectRoot, ModelName));
N = numel(r);
Tend = (N-1)*Ts;
% A fresh MATLAB session must find the same data map used during the build.
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(projectRoot, "Cache"), ...
    "CodeGenFolder", fullfile(projectRoot, "CodeGen"), "createDir", true);
dataDir = fullfile(projectRoot, "simulink", "data");
assert_target_built(projectRoot, "tunable_build_info.mat", Ts);
% Select the deployed common module explicitly; empty arguments open a dialog
% on every connection, including each exp05 trial.
set_param(model, "SimulationMode", "external", ...
    "ExtModeMexArgs", "'192.168.10.3.1.1' 0 16842784"); % Object3, 0x01010020
bufferCapacity = get_buffer_capacity(model);
resetValues = prepare_tunable_trajectory_parameters( ...
    zeros(N, 1), zeros(N, 1), bufferCapacity);
resetValues.p_active = 0;
resetValues.p_servo = 0;
resetValues.p_count = 0;
resetValues.p_allocation_request_id = uint32(0);
feedback = fixed_feedback_coefficients(evalin('base','Kd'),Ts);
resetValues.p_fb_num = feedback.p_fb_num;
resetValues.p_fb_den = feedback.p_fb_den;
setvars(model, resetValues);

archive_measurement_parts(dataDir,runDir,fullfile('raw','previous'));
clear measurement

%% Connect and run
[measurement, metadata] = run_feedforward_capture( ...
    model, N, r, f, Tend, dataDir, Ts, bufferCapacity, runDir, allocationRequestId);
end

function [measurement, metadata] = run_feedforward_capture( ...
        model, N, r, f, Tend, dataDir, Ts, bufferCapacity, runDir, allocationRequestId)
% A function scope guarantees cleanup when capture errors or is interrupted.
% Capture arguments by value: nested cleanup functions can lose shared
% variables while MATLAB destroys the parent workspace.
cleanupGuard = onCleanup(@()cleanup_capture( ...
    model, N, bufferCapacity, dataDir, runDir));
set_param(model, "SimulationCommand", "connect");
wait_for_model_state(model, "ExtModeConnected", "on", 10);

% Finish a zero-length reference with the servo OFF. The generated target
% holds ref_finished after an aborted run; count=0 rebases its
% relative position and closes the previous File Writer before any motion.
set_param(model, "SimulationCommand", "start");
startSettlingTime = 3;
pause(startSettlingTime);
assert(string(get_param(model,"ExtModeConnected"))=="on" && ...
    string(get_param(model,"SimulationStatus"))=="external", ...
    'NikonMotor:ExternalModeDisconnected','External Mode disconnected during startup.');
setvars(model, struct("p_active", 1));
pause(0.1);
setvars(model, struct("p_active", 0));
pause(0.1);

runValues = prepare_tunable_trajectory_parameters(r, f, bufferCapacity);
runValues.p_servo = 0;
runValues.p_allocation_request_id = allocationRequestId;
setvars(model, runValues);
setvars(model, struct("p_servo", 1));
servoSettlingTime = 3;
pause(servoSettlingTime);
setvars(model, struct("p_active", 1));
pause(Tend+1)

reset_and_disconnect(model, N, bufferCapacity);
pause(0.5)

[measurement, metadata] = wait_for_measurement(dataDir, Ts, 10);
if isempty(measurement)
    error("NikonMotor:MeasurementNotFound", ...
        "The feedforward experiment completed without a measurement file.");
end
if ~any(metadata.schema_name == ["feedforward_v1","feedforward_axis_v2"])
    error("NikonMotor:UnexpectedMeasurementSchema", ...
        "Expected a feedforward measurement, but loaded %s.", ...
        metadata.schema_name);
end
if metadata.timestamp_source ~= "tc_yout.logical_time"
    error("NikonMotor:MeasurementTimestampMissing", ...
        "TwinCAT logical timestamps are required for an experiment capture.");
end
archive_measurement_parts(dataDir,runDir);
[~,sourceName,sourceExtension] = fileparts(metadata.source_path);
metadata.target_source_path = metadata.source_path;
metadata.source_path = string(fullfile(runDir,'raw',sourceName+sourceExtension));
cancel(cleanupGuard);
end

function cleanup_capture(model, N, bufferCapacity, dataDir, runDir)
reset_and_disconnect(model, N, bufferCapacity);
try
    archive_measurement_parts(dataDir,runDir);
catch cause
    warning('NikonMotor:RawArchiveFailed','%s',cause.message);
end
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

function reset_and_disconnect(model, N, bufferCapacity)
try
    setvars(model, struct("p_active", 0, "p_servo", 0));
    pause(0.1);
    % motor_config propagates servo OFF through a separate TcCOM context.
    % Retain the request until that command has reached MotorRuntime.
    setvars(model, struct("p_allocation_request_id",uint32(0)));
    % Complete an interrupted reference without recording an extra sample.
    % ref_finished is held by the generated disabled subsystem, so merely
    % setting p_active=0 does not close its file or rebase the next trial.
    setvars(model, struct("p_count", 0, "p_active", 1));
    pause(0.1);
    setvars(model, struct("p_active", 0));
catch cause
    warning("NikonMotor:ResetFailed", "Experiment reset failed: %s", cause.message);
end
try
    status = string(get_param(model, "SimulationStatus"));
    if any(status == ["running", "external", "paused", "initializing"])
        set_param(model, "SimulationCommand", "stop");
        wait_for_model_state(model, "SimulationStatus", "stopped", 5);
    end
catch cause
    warning("NikonMotor:StopFailed", "Experiment stop failed: %s", cause.message);
end
try
    values = prepare_tunable_trajectory_parameters( ...
        zeros(N, 1), zeros(N, 1), bufferCapacity);
    values.p_active = 0;
    values.p_servo = 0;
    values.p_allocation_request_id = uint32(0);
    setvars(model, values);
catch cause
    warning("NikonMotor:ResetFailed", "Experiment reset failed: %s", cause.message);
end
try
    set_param(model, "SimulationCommand", "disconnect");
catch cause
    warning("NikonMotor:DisconnectFailed", ...
        "External-mode disconnect failed: %s", cause.message);
end
end

function [measurement, metadata] = wait_for_measurement(dataDir, Ts, timeout)
started = tic;
while true
    try
        [measurement, ~, ~, ~, metadata] = ...
            load_latest_twincat_measurement(dataDir, Ts);
        if ~isempty(measurement), return; end
    catch cause
        % The writer updates the MAT array header when its asynchronous close
        % finishes. Do not treat an in-progress zero-row header as a capture.
        if cause.identifier ~= "NikonMotor:UnsupportedMeasurementWidth" ...
                || ~contains(cause.message,"contains 0 rows") ...
                || toc(started) >= timeout
            rethrow(cause);
        end
    end
    if toc(started) >= timeout
        error("NikonMotor:MeasurementTimeout","Measurement was not finalized within %.1f seconds.",timeout);
    end
    pause(0.05);
end
end

function wait_for_model_state(model, parameter, expected, timeout)
started = tic;
while toc(started) < timeout
    if string(get_param(model, parameter)) == expected
        return
    end
    pause(0.05);
end
error("NikonMotor:ExternalModeTimeout", ...
    "The model did not reach %s=%s within %.1f seconds.", ...
    parameter, expected, timeout);
end
