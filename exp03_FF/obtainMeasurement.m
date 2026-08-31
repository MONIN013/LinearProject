%% Prepare the external-mode experiment
model = string(bdroot);
projectRoot = fileparts(fileparts(mfilename("fullpath")));
dataDir = fullfile(projectRoot, "simulink", "data");
assert_target_built(projectRoot, "tunable_build_info.mat", Ts);
set_param(model, "SimulationMode", "external");
bufferCapacity = get_buffer_capacity(model);
resetValues = prepare_tunable_trajectory_parameters( ...
    zeros(N, 1), zeros(N, 1), bufferCapacity);
resetValues.p_active = 0;
resetValues.p_servo = 0;
setvars(model, resetValues);

% The next capture must not be confused with parts from an earlier run.
parts = dir(fullfile(dataDir, "measurement_*.mat"));
for k = 1:numel(parts)
    delete(fullfile(parts(k).folder, parts(k).name));
end
clear measurement

%% Connect and run
measurement = run_feedforward_capture( ...
    model, N, r, f, Tend, dataDir, Ts, bufferCapacity);

function measurement = run_feedforward_capture( ...
        model, N, r, f, Tend, dataDir, Ts, bufferCapacity)
% A function scope guarantees cleanup when capture errors or is interrupted.
cleanupGuard = onCleanup(@()reset_and_disconnect(model, N, bufferCapacity));
set_param(model, "SimulationCommand", "connect");
pause(2);

runValues = prepare_tunable_trajectory_parameters(r, f, bufferCapacity);
runValues.p_servo = 0;
setvars(model, runValues);
setvars(model, struct("p_servo", 1));
servoSettlingTime = 3;
pause(servoSettlingTime);
set_param(model, "SimulationCommand", "start");
startSettlingTime = 3;
pause(startSettlingTime);
setvars(model, struct("p_active", 1));
pause(Tend+1)

clear cleanupGuard
pause(0.5)

[measurement, ~, ~, ~, metadata] = ...
    load_latest_twincat_measurement(dataDir, Ts);
if isempty(measurement)
    error("NikonMotor:MeasurementNotFound", ...
        "The feedforward experiment completed without a measurement file.");
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
    values = prepare_tunable_trajectory_parameters( ...
        zeros(N, 1), zeros(N, 1), bufferCapacity);
    values.p_active = 0;
    values.p_servo = 0;
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
