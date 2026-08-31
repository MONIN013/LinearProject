[~, model] = fileparts(ModelName);
model = string(model);
activeBlock = BlockPaths{Index_active};
servoBlock = BlockPaths{Index_servo};
cleanupGuard = onCleanup(@()reset_and_disconnect_chirp( ...
    model, activeBlock, servoBlock));

simulink_set_constant(activeBlock, 0);
set_param(servoBlock, "Value", "0");
pause(0.5);

dataDir = fullfile(projectRoot, "simulink", "data");
parts = dir(fullfile(dataDir, "measurement_*.mat"));
for k = 1:numel(parts)
    delete(fullfile(parts(k).folder, parts(k).name));
end

set_param(model, "SimulationCommand", "connect");
set_param(servoBlock, "Value", "1");
pause(0.5);
set_param(model, "SimulationCommand", "start");
pause(3);
simulink_set_constant(activeBlock, 1);
pause(Tend + 1);
clear cleanupGuard
pause(0.5);

[measurement, measurement_time_raw, measurement_time, matPath, ...
    measurement_metadata] = load_latest_twincat_measurement(dataDir, Ts);
if isempty(measurement)
    return
end
if measurement_metadata.timestamp_source ~= "tc_yout.logical_time"
    error("NikonMotor:MeasurementTimestampMissing", ...
        "TwinCAT logical timestamps are required for an experiment capture.");
end
measurement_source_path = string(matPath);

function reset_and_disconnect_chirp(model, activeBlock, servoBlock)
try
    simulink_set_constant(activeBlock, 0);
    set_param(servoBlock, "Value", "0");
catch cause
    warning("NikonMotor:ResetFailed", ...
        "Chirp safety reset failed: %s", cause.message);
end
try
    set_param(model, "SimulationCommand", "disconnect");
catch cause
    warning("NikonMotor:DisconnectFailed", ...
        "External-mode disconnect failed: %s", cause.message);
end
end
