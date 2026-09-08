runDir = create_run_directory(fullfile(projectRoot, "data", "fb"), "feedback");
[measurement, measurement_time_raw, measurement_time, measurement_metadata, ...
    measurement_source_path, measurement_schema_version, measurement_signal_names] = ...
    capture_feedback_measurement(ModelName, BlockPaths, Index_active, Index_servo, ...
    projectRoot, Tend, Ts, runDir);

function [measurement, measurement_time_raw, measurement_time, ...
        measurement_metadata, measurement_source_path, ...
        measurement_schema_version, measurement_signal_names] = ...
        capture_feedback_measurement(ModelName, BlockPaths, Index_active, Index_servo, ...
        projectRoot, Tend, Ts, runDir)
assert_target_built(projectRoot, "feedback_build_info.mat", Ts);
[~, model] = fileparts(ModelName);
model = string(model);
activeBlock = BlockPaths{Index_active};
servoBlock = BlockPaths{Index_servo};
dataDir = fullfile(projectRoot, "simulink", "data");
archive_measurement_parts(dataDir);
finished = false;
cleanupGuard = onCleanup(@cleanup_capture);

simulink_set_constant(activeBlock, 0);
set_param(servoBlock, "Value", "0"); % 0: servo off, 1: servo on
pause(0.5);
set_param(model, "SimulationCommand", "connect");
set_param(servoBlock, "Value", "1"); % 0: servo off, 1: servo on
pause(3);
set_param(model, "SimulationCommand", "start");
pause(3);
simulink_set_constant(activeBlock, 1);
pause(Tend + 1);
reset_and_disconnect_feedback(model, activeBlock, servoBlock);
pause(0.5);

[measurement, measurement_time_raw, measurement_time, matPath, ...
    measurement_metadata] = load_latest_twincat_measurement(dataDir, Ts);
archivedPaths = archive_measurement_parts(dataDir, runDir);
finished = true;
clear cleanupGuard
measurement_source_path = "";
measurement_schema_version = "";
measurement_signal_names = strings(0, 1);
if isempty(measurement)
    return
end
if measurement_metadata.timestamp_source ~= "tc_yout.logical_time"
    error("NikonMotor:MeasurementTimestampMissing", ...
        "TwinCAT logical timestamps are required for an experiment capture.");
end
measurement_source_path = string(matPath);
measurement_schema_version = measurement_metadata.schema_version;
measurement_signal_names = measurement_metadata.signal_names;
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
        reset_and_disconnect_feedback(model, activeBlock, servoBlock);
        archive_measurement_parts(dataDir, runDir);
    end
end

function reset_and_disconnect_feedback(model, activeBlock, servoBlock)
try
    simulink_set_constant(activeBlock, 0);
    set_param(servoBlock, "Value", "0");
catch cause
    warning("NikonMotor:ResetFailed", ...
        "Feedback safety reset failed: %s", cause.message);
end
try
    set_param(model, "SimulationCommand", "disconnect");
catch cause
    warning("NikonMotor:DisconnectFailed", ...
        "External-mode disconnect failed: %s", cause.message);
end
end
