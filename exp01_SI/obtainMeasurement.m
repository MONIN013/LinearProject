runDir = create_run_directory(fullfile(projectRoot, "data", "si"), "identification");
[measurement, measurement_time_raw, measurement_time, measurement_metadata, ...
    measurement_source_path] = capture_chirp_measurement( ...
    ModelName, BlockPaths, Index_active, Index_servo, projectRoot, Tend, Ts, runDir);

function [measurement, measurement_time_raw, measurement_time, ...
        measurement_metadata, measurement_source_path] = capture_chirp_measurement( ...
        ModelName, BlockPaths, Index_active, Index_servo, projectRoot, Tend, Ts, runDir)
[~, model] = fileparts(ModelName);
model = string(model);
activeBlock = BlockPaths{Index_active};
servoBlock = BlockPaths{Index_servo};
dataDir = fullfile(projectRoot, "simulink", "data");
archive_measurement_parts(dataDir);
finished = false;
cleanupGuard = onCleanup(@cleanup_capture);

simulink_set_constant(activeBlock, 0);
set_param(servoBlock, "Value", "0");
pause(0.5);
set_param(model, "SimulationCommand", "connect");
set_param(servoBlock, "Value", "1");
pause(0.5);
set_param(model, "SimulationCommand", "start");
pause(3);
simulink_set_constant(activeBlock, 1);
pause(Tend + 1);
reset_and_disconnect_chirp(model, activeBlock, servoBlock);
pause(0.5);

[measurement, measurement_time_raw, measurement_time, matPath, ...
    measurement_metadata] = load_latest_twincat_measurement(dataDir, Ts);
archivedPaths = archive_measurement_parts(dataDir, runDir);
finished = true;
clear cleanupGuard
measurement_source_path = "";
if isempty(measurement)
    return
end
if measurement_metadata.timestamp_source ~= "tc_yout.logical_time"
    error("NikonMotor:MeasurementTimestampMissing", ...
        "TwinCAT logical timestamps are required for an experiment capture.");
end
measurement_source_path = string(matPath);
[~, sourceName, sourceExt] = fileparts(matPath);
matchingPath = archivedPaths(endsWith(archivedPaths, ...
    string(sourceName) + string(sourceExt)));
if ~isempty(matchingPath)
    measurement_source_path = matchingPath(end);
end

    function cleanup_capture
        if finished
            return
        end
        reset_and_disconnect_chirp(model, activeBlock, servoBlock);
        archive_measurement_parts(dataDir, runDir);
    end
end

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
