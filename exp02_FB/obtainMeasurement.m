%% Capture through the common tunable model and retain MATLAB records
runDir = create_run_directory(fullfile(projectRoot, "data", "fb"), "feedback");
load_system(fullfile(projectRoot, ModelName));
pre = read_tunable_idle_state(Ts);
assert(abs(pre.positionCount-homing.final_count)<=1000, ...
    'NikonMotor:StartPositionChanged', 'Stage position changed after Homing.');
measurement = [];
post = [];
try
    [measurement, ~, measurement_metadata] = capture_tunable_trajectory( ...
        ModelName, set_ref, set_ff, Ts, runDir);
    post = read_tunable_idle_state(Ts);
    assert(isequal(size(measurement),[10,numel(set_ref)]) && ...
        all(isfinite(measurement),'all'), ...
        'NikonMotor:InvalidCapture', 'Expected a finite 10-by-N capture.');
    assert(all(diff(measurement(1,:))==1), ...
        'NikonMotor:LostSamples', 'Measurement contains missing or out-of-order samples.');
    assert(max(abs(measurement(9,:)'-[0;set_ref(1:end-1)]))<1e-7 && ...
        max(abs(measurement(7,:)'-[0;set_ff(1:end-1)]))<1e-7, ...
        'NikonMotor:CaptureMismatch', 'Recorded reference/FF differs from this trial.');
    assert(max(abs(measurement(3,:)))<=MAX_INPUT+1e-9, ...
        'NikonMotor:CurrentLimit', 'Recorded current command exceeds the configured limit.');
    measurement_time_raw = measurement_metadata.measurement_time_raw;
    measurement_time = measurement_metadata.measurement_time;
    measurement_source_path = measurement_metadata.source_path;
    measurement_schema_version = measurement_metadata.schema_version;
    measurement_signal_names = measurement_metadata.signal_names;
catch cause
    failure = struct('message',cause.message,'identifier',cause.identifier);
    if isempty(post)
        try
            post = read_tunable_idle_state(Ts);
        catch stopCause
            failure.stopUnverified = stopCause.message;
        end
    end
    save_experiment_result(runDir, 'capture_failed', struct( ...
        'measurement',measurement,'pre',pre,'post',post,'failure',failure, ...
        'set_ref',set_ref,'set_ff',set_ff,'Kd',Kd,'Ts',Ts,'homing',homing));
    rethrow(cause);
end
