assert_target_built(projectRoot, "feedback_build_info.mat", Ts);
[~, model] = fileparts(ModelName);
model = string(model);
activeBlock = BlockPaths{Index_active};
servoBlock = BlockPaths{Index_servo};
cleanupGuard = onCleanup(@()reset_and_disconnect_feedback( ...
    model, activeBlock, servoBlock));
simulink_set_constant(activeBlock, 0);
set_param(servoBlock,"Value","0"); % 0: servo off, 1: servo on
% simulink_set_constant(BlockPaths{Index_output}, string(output_type)); % 1: load-side, 2: motor-side
pause(0.5);
if ~isempty(dir("simulink/data/measurement_*.mat"))
    delete("simulink/data/measurement_*.mat");
    clear("measurement_*");
end
set_param(model,'SimulationCommand','connect');
set_param(servoBlock,"Value","1"); % 0: servo off, 1: servo on
pause(3);
set_param(model,'SimulationCommand','start');
% finish_rto = get_param(BlockPaths{Index_finish},'RunTimeObject'); % obtain runtime object inside of simulink to detemine flag condition
pause(3);
simulink_set_constant(activeBlock, 1);
pause(Tend+1);
clear cleanupGuard
pause(0.5);
% retrieve data
% data_files = dir("simulink/data/measurement_*.mat");
% file_names = [];
% for data_file_name = string({data_files.name})
%     [~, file_name, ~] = fileparts(data_file_name);
%     file_names = [file_name, file_names];
% end
% % [~, file_names, ~] = fileparts({data_files.name}); % for recent matlab version
% file_ids = erase(file_names,"measurement_part");
% target_id = max(sort(str2double(file_ids))); % choose file with largest id
% load("simulink/data/measurement_part" + string(target_id) + ".mat");
% measurement = eval("measurement_" + string(target_id));

dataDir = "simulink/data";
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
measurement_schema_version = measurement_metadata.schema_version;
measurement_signal_names = measurement_metadata.signal_names;

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
