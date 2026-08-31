function [measurement, measurementTimeRaw, measurementTime, matPath, metadata] = ...
    load_latest_twincat_measurement(dataDir, samplePeriod)
%LOAD_LATEST_TWINCAT_MEASUREMENT Load and validate the newest File Writer part.
%
% The File Writer timestamp is Simulink logical task time, not wall-clock or
% EtherCAT distributed-clock time. Supported layouts are position-feedback
% v2/v3 and the ten-signal feedforward v1 layout.

if nargin < 1 || strlength(string(dataDir)) == 0
    dataDir = fullfile("simulink", "data");
end
if nargin < 2 || isempty(samplePeriod)
    samplePeriod = 0.000125;
end
validateattributes(samplePeriod, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'}, mfilename, 'samplePeriod');

parts = dir(fullfile(dataDir, "measurement_part*.mat"));
if isempty(parts)
    warning("NikonMotor:MeasurementNotFound", ...
        "No measurement file was found: %s", ...
        fullfile(dataDir, "measurement_part*.mat"));
    measurement = [];
    measurementTimeRaw = [];
    measurementTime = [];
    matPath = "";
    metadata = localEmptyMetadata(samplePeriod);
    return
end

ids = nan(size(parts));
for i = 1:numel(parts)
    parsed = sscanf(parts(i).name, "measurement_part%d.mat");
    if isscalar(parsed)
        ids(i) = parsed;
    end
end
if all(isnan(ids))
    error("NikonMotor:InvalidMeasurementPartName", ...
        "No measurement part filename contained a numeric part identifier.");
end

[~, iMax] = max(ids);
matPath = string(fullfile(parts(iMax).folder, parts(iMax).name));
loaded = load(matPath, "tc_yout");
if ~isfield(loaded, "tc_yout")
    error("NikonMotor:MissingTwinCATOutput", ...
        "Variable tc_yout was not found in %s.", matPath);
end

try
    measurement = horzcat(loaded.tc_yout.data);
catch cause
    error("NikonMotor:InvalidTwinCATOutput", ...
        "tc_yout.data in %s could not be concatenated: %s", ...
        matPath, cause.message);
end
if ~isnumeric(measurement) || ~ismatrix(measurement)
    error("NikonMotor:InvalidTwinCATOutput", ...
        "tc_yout.data in %s must form a numeric matrix.", matPath);
end

signalCount = size(measurement, 1);
[schemaVersion, schemaName, signalNames] = localSchema(signalCount);

if isfield(loaded.tc_yout, "time")
    measurementTimeRaw = double(horzcat(loaded.tc_yout.time));
else
    measurementTimeRaw = [];
end

sampleCount = size(measurement, 2);
if numel(measurementTimeRaw) == sampleCount && sampleCount > 0 ...
        && all(isfinite(measurementTimeRaw))
    measurementTimeRaw = reshape(measurementTimeRaw, 1, []);
    measurementTime = measurementTimeRaw - measurementTimeRaw(1);
    timestampSource = "tc_yout.logical_time";
    if sampleCount > 1
        observedSamplePeriod = median(diff(measurementTimeRaw));
        tolerance = max(1e-9, 1e-6*samplePeriod);
        if observedSamplePeriod <= 0 || ...
                abs(observedSamplePeriod - samplePeriod) > tolerance
            error("NikonMotor:MeasurementSamplePeriodMismatch", ...
                "Configured Ts is %.9g s, but the measurement logical " + ...
                "time has a median period of %.9g s: %s", ...
                samplePeriod, observedSamplePeriod, matPath);
        end
    else
        observedSamplePeriod = nan;
    end
else
    measurementTimeRaw = nan(1, sampleCount);
    measurementTime = (0:(sampleCount - 1)) .* double(samplePeriod);
    timestampSource = "synthetic_sample_period";
    observedSamplePeriod = nan;
end

metadata = struct();
metadata.schema_version = schemaVersion;
metadata.schema_name = schemaName;
metadata.timestamp_source = timestampSource;
metadata.sample_period_s = double(samplePeriod);
metadata.observed_sample_period_s = observedSamplePeriod;
metadata.signal_names = signalNames;
metadata.source_path = matPath;
metadata.sample_count = uint32(sampleCount);
metadata.signal_count = uint16(signalCount);
metadata.time_is_wall_clock = false;
end

function [schemaVersion, schemaName, signalNames] = localSchema(signalCount)
legacyNames = [ ...
    "count", ...
    "tracking_error_m", ...
    "reference_m", ...
    "control_current_A", ...
    "position_m", ...
    "velocity_m_per_s", ...
    "torque_actual_A"];
diagnosticNames = [ ...
    "panasonic_position_raw_count", ...
    "panasonic_velocity_raw_count", ...
    "panasonic_wcstate", ...
    "panasonic_input_toggle", ...
    "copley_wcstate", ...
    "copley_input_toggle", ...
    "panasonic_statusword", ...
    "panasonic_error_code", ...
    "task_cycle_time_exceeded", ...
    "task_exceed_counter"];
feedforwardNames = [ ...
    "count", ...
    "tracking_error_m", ...
    "control_current_A", ...
    "velocity_m_per_s", ...
    "position_m", ...
    "torque_actual_A", ...
    "feedforward_current_A", ...
    "absolute_position_m", ...
    "reference_m", ...
    "quantized_reference_m"];

switch signalCount
    case 7
        schemaVersion = uint16(2);
        schemaName = "position_feedback_v2";
        signalNames = legacyNames;
    case 10
        schemaVersion = uint16(1);
        schemaName = "feedforward_v1";
        signalNames = feedforwardNames;
    case 17
        schemaVersion = uint16(3);
        schemaName = "position_feedback_v3";
        signalNames = [legacyNames, diagnosticNames];
    otherwise
        error("NikonMotor:UnsupportedMeasurementWidth", ...
            "tc_yout.data contains %d rows. Supported layouts are " + ...
            "feedforward v1 (10 rows), position-feedback v2 (7 rows), " + ...
            "and position-feedback v3 (17 rows).", signalCount);
end
end

function metadata = localEmptyMetadata(samplePeriod)
metadata = struct();
metadata.schema_version = uint16(0);
metadata.schema_name = "missing";
metadata.timestamp_source = "missing";
metadata.sample_period_s = double(samplePeriod);
metadata.observed_sample_period_s = nan;
metadata.signal_names = strings(1, 0);
metadata.source_path = "";
metadata.sample_count = uint32(0);
metadata.signal_count = uint16(0);
metadata.time_is_wall_clock = false;
end
