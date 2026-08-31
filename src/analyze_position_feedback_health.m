function report = analyze_position_feedback_health(source, varargin)
%ANALYZE_POSITION_FEEDBACK_HEALTH Classify motion-time position hold events.
%
% SOURCE may be:
%   * a 7xN or 17xN measurement matrix;
%   * a struct containing measurement, signal_names, and time;
%   * a MAT-file path containing that struct-like workspace;
%   * a raw TwinCAT File Writer MAT-file containing tc_yout.
%
% Classification is evidence ordered. A strong upstream observation is not
% replaced by a weaker correlated task-exceed observation.

parser = inputParser;
parser.addParameter("SamplePeriod", 0.000125, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
parser.addParameter("MinimumHold_s", 0.010, ...
    @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
parser.parse(varargin{:});
options = parser.Results;

signals = localReadSignals(source, double(options.SamplePeriod));
samplePeriod = localSamplePeriod(signals.time_s, double(options.SamplePeriod));
[runStart, runEnd] = localFindHoldEvents( ...
    signals.position_m, signals.reference_m, ...
    samplePeriod, double(options.MinimumHold_s));

eventCount = numel(runStart);
if eventCount == 0
    report = localEmptyReport(signals);
    return
end

startIndex = uint32(runStart);
endIndex = uint32(runEnd);
sampleCount = uint32(runEnd - runStart + 1);
startTime_s = zeros(eventCount, 1);
endTime_s = zeros(eventCount, 1);
duration_s = zeros(eventCount, 1);
heldPosition_m = zeros(eventCount, 1);
positionJumpAfter_m = zeros(eventCount, 1);
referenceChange_m = zeros(eventCount, 1);
peakCommand_A = zeros(eventCount, 1);
rawPositionAdvanced = false(eventCount, 1);
rawPositionHeld = false(eventCount, 1);
panasonicWcInvalid = false(eventCount, 1);
copleyWcInvalid = false(eventCount, 1);
panasonicToggleAdvanced = false(eventCount, 1);
copleyToggleAdvanced = false(eventCount, 1);
taskFlagSeen = false(eventCount, 1);
taskCounterDelta = zeros(eventCount, 1, "uint64");
taskCorrelated = false(eventCount, 1);
cause = strings(eventCount, 1);

for i = 1:eventCount
    first = runStart(i);
    last = runEnd(i);
    after = min(numel(signals.position_m), last + 1);
    eventIndices = first:last;
    diagnosticIndices = max(1, first - 1):last;

    startTime_s(i) = signals.time_s(first);
    endTime_s(i) = signals.time_s(last);
    duration_s(i) = signals.time_s(last) - signals.time_s(first);
    heldPosition_m(i) = signals.position_m(first);
    positionJumpAfter_m(i) = ...
        signals.position_m(after) - signals.position_m(last);
    referenceChange_m(i) = ...
        signals.reference_m(last) - signals.reference_m(first);
    peakCommand_A(i) = max(abs(signals.control_current_A(eventIndices)));

    rawPositionAdvanced(i) = localAdvanced( ...
        signals.panasonic_position_raw_count(eventIndices));
    rawPositionHeld(i) = localStale( ...
        signals.panasonic_position_raw_count(eventIndices));
    panasonicWcInvalid(i) = localWcInvalid( ...
        signals.panasonic_wcstate(eventIndices));
    copleyWcInvalid(i) = localWcInvalid( ...
        signals.copley_wcstate(eventIndices));
    panasonicToggleAdvanced(i) = localAdvanced( ...
        signals.panasonic_input_toggle(eventIndices));
    copleyToggleAdvanced(i) = localAdvanced( ...
        signals.copley_input_toggle(eventIndices));
    taskFlagSeen(i) = localFlagSeen( ...
        signals.task_cycle_time_exceeded(eventIndices));
    taskCounterDelta(i) = localCounterIncrease( ...
        signals.task_exceed_counter(diagnosticIndices));
    taskCorrelated(i) = taskFlagSeen(i) || taskCounterDelta(i) > 0;

    cause(i) = localClassifyEvent( ...
        rawPositionAdvanced(i), rawPositionHeld(i), ...
        panasonicWcInvalid(i), copleyWcInvalid(i), ...
        panasonicToggleAdvanced(i), copleyToggleAdvanced(i), ...
        signals.panasonic_input_toggle(eventIndices), ...
        signals.copley_input_toggle(eventIndices), ...
        taskCorrelated(i));
end

events = table( ...
    startIndex, endIndex, sampleCount, ...
    startTime_s, endTime_s, duration_s, heldPosition_m, ...
    positionJumpAfter_m, referenceChange_m, peakCommand_A, ...
    rawPositionAdvanced, rawPositionHeld, ...
    panasonicWcInvalid, copleyWcInvalid, ...
    panasonicToggleAdvanced, copleyToggleAdvanced, ...
    taskFlagSeen, taskCounterDelta, taskCorrelated, cause, ...
    'VariableNames', { ...
    'start_index', 'end_index', 'sample_count', ...
    'start_time_s', 'end_time_s', 'duration_s', 'held_position_m', ...
    'position_jump_after_m', 'reference_change_m', 'peak_command_A', ...
    'raw_position_advanced', 'raw_position_held', ...
    'panasonic_wc_invalid', 'copley_wc_invalid', ...
    'panasonic_toggle_advanced', 'copley_toggle_advanced', ...
    'task_cycle_time_exceeded_seen', 'task_exceed_counter_delta', ...
    'task_exceed_correlated', 'cause'});

primaryCause = localExperimentCause(cause);
report = struct();
report.source = signals.source;
report.schema_version = signals.schema_version;
report.signal_names = signals.signal_names;
report.events = events;
report.event_count = uint32(eventCount);
report.longest_hold_s = max(duration_s);
report.velocity_endpoint_seen = ...
    any(abs(signals.velocity_m_per_s) >= 214.7);
report.feedback_path_stale = true;
report.io_diagnostics_available = signals.io_diagnostics_available;
report.cause = primaryCause;
report.primary_cause = primaryCause;
report.interpretation = localInterpretation(primaryCause);
report.summary = localSummary(cause, taskCorrelated, ...
    signals.task_cycle_time_exceeded, signals.task_exceed_counter);
end

function signals = localReadSignals(source, samplePeriod)
signals = struct();
if isnumeric(source)
    loaded = struct("measurement", source);
    sourceName = "numeric input";
elseif ischar(source) || (isstring(source) && isscalar(source))
    sourceName = string(source);
    loaded = load(sourceName);
elseif isstruct(source)
    sourceName = "struct input";
    loaded = source;
else
    error("NikonMotor:UnsupportedMeasurement", ...
        "Source must be a numeric matrix, struct, or scalar MAT-file path.");
end

if isfield(loaded, "measurement")
    measurement = loaded.measurement;
    names = localFindNames(loaded, size(measurement, 1));
    time = localFindTime(loaded);
elseif isfield(loaded, "tc_yout")
    measurement = horzcat(loaded.tc_yout.data);
    names = localFindNames(loaded, size(measurement, 1));
    if isfield(loaded.tc_yout, "time")
        time = double(horzcat(loaded.tc_yout.time));
    else
        time = [];
    end
elseif all(isfield(loaded, {'y', 'v', 'r', 'u'}))
    [measurement, names] = localLegacyWorkspace(loaded);
    time = localFindTime(loaded);
else
    error("NikonMotor:UnsupportedMeasurement", ...
        ["Input must contain measurement, tc_yout, or the legacy " ...
        "y/v/r/u variables."]);
end

if ~isnumeric(measurement) || ~ismatrix(measurement)
    error("NikonMotor:InvalidMeasurement", ...
        "measurement must be a numeric matrix.");
end
[schemaVersion, canonicalNames] = localSchema(size(measurement, 1));
names = reshape(string(names), 1, []);
if numel(names) ~= size(measurement, 1) ...
        || ~isequal(names, canonicalNames)
    error("NikonMotor:InvalidSignalNames", ...
        "signal_names must exactly match the schema v%d row order.", ...
        schemaVersion);
end

sampleCount = size(measurement, 2);
time = double(time(:));
if numel(time) == sampleCount && sampleCount > 0 && all(isfinite(time))
    time = time - time(1);
else
    time = (0:(sampleCount - 1))' .* samplePeriod;
end

signals.source = sourceName;
signals.schema_version = schemaVersion;
signals.signal_names = names;
signals.time_s = time;
signals.count = localSignal(measurement, names, "count");
signals.reference_m = localSignal(measurement, names, "reference_m");
signals.control_current_A = ...
    localSignal(measurement, names, "control_current_A");
signals.position_m = localSignal(measurement, names, "position_m");
signals.velocity_m_per_s = ...
    localSignal(measurement, names, "velocity_m_per_s");
signals.panasonic_position_raw_count = ...
    localSignal(measurement, names, ...
    "panasonic_position_raw_count", sampleCount);
signals.panasonic_velocity_raw_count = ...
    localSignal(measurement, names, ...
    "panasonic_velocity_raw_count", sampleCount);
signals.panasonic_wcstate = ...
    localSignal(measurement, names, "panasonic_wcstate", sampleCount);
signals.panasonic_input_toggle = ...
    localSignal(measurement, names, ...
    "panasonic_input_toggle", sampleCount);
signals.copley_wcstate = ...
    localSignal(measurement, names, "copley_wcstate", sampleCount);
signals.copley_input_toggle = ...
    localSignal(measurement, names, "copley_input_toggle", sampleCount);
signals.task_cycle_time_exceeded = ...
    localSignal(measurement, names, ...
    "task_cycle_time_exceeded", sampleCount);
signals.task_exceed_counter = ...
    localSignal(measurement, names, ...
    "task_exceed_counter", sampleCount);
signals.io_diagnostics_available = schemaVersion == 3 ...
    && any(isfinite(signals.panasonic_wcstate)) ...
    && any(isfinite(signals.panasonic_input_toggle));
end

function names = localFindNames(loaded, rowCount)
if isfield(loaded, "signal_names")
    names = loaded.signal_names;
elseif isfield(loaded, "measurement_signal_names")
    names = loaded.measurement_signal_names;
elseif isfield(loaded, "metadata") ...
        && isfield(loaded.metadata, "signal_names")
    names = loaded.metadata.signal_names;
elseif isfield(loaded, "measurement_metadata") ...
        && isfield(loaded.measurement_metadata, "signal_names")
    names = loaded.measurement_metadata.signal_names;
else
    [~, names] = localSchema(rowCount);
end
end

function time = localFindTime(loaded)
candidateNames = [ ...
    "time", "measurement_time", "measurementTime", ...
    "t", "tc_time_raw", "measurement_time_raw"];
time = [];
for name = candidateNames
    if isfield(loaded, name)
        time = loaded.(name);
        return
    end
end
end

function [measurement, names] = localLegacyWorkspace(loaded)
sampleCount = numel(loaded.y);
required = {'v', 'r', 'u'};
for i = 1:numel(required)
    if numel(loaded.(required{i})) ~= sampleCount
        error("NikonMotor:InvalidMeasurement", ...
            "Legacy y/v/r/u variables must have equal lengths.");
    end
end
measurement = zeros(7, sampleCount);
measurement(1, :) = 0:(sampleCount - 1);
if isfield(loaded, "e") && numel(loaded.e) == sampleCount
    measurement(2, :) = reshape(double(loaded.e), 1, []);
end
measurement(3, :) = reshape(double(loaded.r), 1, []);
measurement(4, :) = reshape(double(loaded.u), 1, []);
measurement(5, :) = reshape(double(loaded.y), 1, []);
measurement(6, :) = reshape(double(loaded.v), 1, []);
if isfield(loaded, "torque") && numel(loaded.torque) == sampleCount
    measurement(7, :) = reshape(double(loaded.torque), 1, []);
end
[~, names] = localSchema(7);
end

function values = localSignal(measurement, names, name, missingLength)
index = find(names == name, 1);
if isempty(index)
    if nargin < 4
        error("NikonMotor:MissingRequiredSignal", ...
            "Required signal %s is missing.", name);
    end
    values = nan(missingLength, 1);
else
    values = double(measurement(index, :))';
end
end

function [schemaVersion, names] = localSchema(rowCount)
legacyNames = [ ...
    "count", "tracking_error_m", "reference_m", "control_current_A", ...
    "position_m", "velocity_m_per_s", "torque_actual_A"];
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
switch rowCount
    case 7
        schemaVersion = uint16(2);
        names = legacyNames;
    case 17
        schemaVersion = uint16(3);
        names = [legacyNames, diagnosticNames];
    otherwise
        error("NikonMotor:UnsupportedMeasurementWidth", ...
            "measurement contains %d rows. Supported layouts are " + ...
            "schema v2 (7 rows) and schema v3 (17 rows).", rowCount);
end
end

function samplePeriod = localSamplePeriod(time, fallback)
delta = diff(time);
delta = delta(isfinite(delta) & delta > 0);
if isempty(delta)
    samplePeriod = fallback;
else
    samplePeriod = median(delta);
end
end

function [runStart, runEnd] = localFindHoldEvents( ...
        position, reference, samplePeriod, minimumHold_s)
position = position(:);
reference = reference(:);
if numel(position) < 2
    runStart = zeros(0, 1);
    runEnd = zeros(0, 1);
    return
end

samePosition = isfinite(position(1:end-1)) ...
    & isfinite(position(2:end)) ...
    & diff(position) == 0;
edges = diff([false; samePosition; false]);
runStart = find(edges == 1);
runEnd = find(edges == -1);
minimumSamples = max(2, ceil(minimumHold_s / samplePeriod) + 1);
keep = false(size(runStart));
for i = 1:numel(runStart)
    indices = runStart(i):runEnd(i);
    referenceMoved = any(diff(reference(indices)) ~= 0);
    keep(i) = numel(indices) >= minimumSamples && referenceMoved;
end
runStart = runStart(keep);
runEnd = runEnd(keep);
end

function value = localWcInvalid(values)
value = any(isfinite(values) & values ~= 0);
end

function value = localFlagSeen(values)
value = any(isfinite(values) & values ~= 0);
end

function value = localAdvanced(values)
values = double(values(:));
valid = isfinite(values);
value = false;
for i = 2:numel(values)
    if valid(i - 1) && valid(i) && values(i) ~= values(i - 1)
        value = true;
        return
    end
end
end

function value = localStale(values)
values = double(values(:));
validCount = nnz(isfinite(values));
value = validCount >= 2 && ~localAdvanced(values);
end

function increase = localCounterIncrease(values)
invalidValue = double(intmax("uint32"));
values = double(values(:));
increase = uint64(0);
for i = 2:numel(values)
    previous = values(i - 1);
    current = values(i);
    validPair = isfinite(previous) && isfinite(current) ...
        && previous ~= invalidValue && current ~= invalidValue ...
        && previous >= 0 && current >= 0;
    if validPair && current > previous
        increase = increase + uint64(current - previous);
    end
end
end

function cause = localClassifyEvent( ...
        rawAdvanced, rawHeld, panasonicWcInvalid, copleyWcInvalid, ...
        panasonicToggleAdvanced, copleyToggleAdvanced, ...
        panasonicToggle, copleyToggle, taskCorrelated)
panasonicToggleStale = localStale(panasonicToggle);
copleyToggleStale = localStale(copleyToggle);

if rawAdvanced
    cause = "virtual_cst_feedback_mapping_stall";
elseif panasonicWcInvalid && copleyWcInvalid
    cause = "shared_ethercat_process_data_invalid";
elseif panasonicWcInvalid && ~copleyWcInvalid
    cause = "panasonic_ethercat_process_data_invalid";
elseif panasonicToggleStale && copleyToggleStale
    cause = "shared_valid_telegram_stall";
elseif panasonicToggleStale && copleyToggleAdvanced
    cause = "panasonic_valid_telegram_stall";
elseif panasonicToggleAdvanced && rawHeld
    cause = "panasonic_drive_or_encoder_value_generation_stall";
elseif taskCorrelated
    cause = "motor_runtime_task_exceed_correlated";
else
    cause = "unknown";
end
end

function primaryCause = localExperimentCause(causes)
priority = [ ...
    "virtual_cst_feedback_mapping_stall", ...
    "shared_ethercat_process_data_invalid", ...
    "panasonic_ethercat_process_data_invalid", ...
    "shared_valid_telegram_stall", ...
    "panasonic_valid_telegram_stall", ...
    "panasonic_drive_or_encoder_value_generation_stall", ...
    "motor_runtime_task_exceed_correlated", ...
    "unknown"];
primaryCause = "unknown";
for candidate = priority
    if any(causes == candidate)
        primaryCause = candidate;
        return
    end
end
end

function summary = localSummary(causes, taskCorrelated, taskFlag, taskCounter)
[causeNames, ~, group] = unique(causes, "stable");
causeCount = zeros(numel(causeNames), 1, "uint32");
for i = 1:numel(causeNames)
    causeCount(i) = uint32(nnz(group == i));
end
summary = struct();
summary.cause_counts = table(causeNames, causeCount, ...
    'VariableNames', {'cause', 'event_count'});
summary.task_exceed_correlated_event_count = ...
    uint32(nnz(taskCorrelated));
summary.task_exceed_correlated = any(taskCorrelated);
summary.task_cycle_time_exceeded_seen = localFlagSeen(taskFlag);
summary.task_exceed_counter_total_increase = ...
    localCounterIncrease(taskCounter);
summary.task_exceed_counter_invalid_sample_count = ...
    uint32(nnz(taskCounter == double(intmax("uint32"))));
end

function text = localInterpretation(cause)
switch cause
    case "virtual_cst_feedback_mapping_stall"
        text = [ ...
            "Panasonic raw position advances while the virtual position is " ...
            "held; the PLC-to-TcCOM virtual-CST feedback mapping stalled."];
    case "shared_ethercat_process_data_invalid"
        text = "Both EtherCAT slaves report invalid process data.";
    case "panasonic_ethercat_process_data_invalid"
        text = "Only the Panasonic EtherCAT process data is invalid.";
    case "shared_valid_telegram_stall"
        text = "Neither slave receives new valid EtherCAT telegrams.";
    case "panasonic_valid_telegram_stall"
        text = ...
            "Panasonic valid telegrams stop while Copley telegrams continue.";
    case "panasonic_drive_or_encoder_value_generation_stall"
        text = [ ...
            "Panasonic telegrams continue but its raw position remains held; " ...
            "inspect drive or encoder value generation."];
    case "motor_runtime_task_exceed_correlated"
        text = "The hold is correlated with a MotorRuntime task exceed.";
    case "no_long_feedback_hold_detected"
        text = "No motion-time position hold exceeded the threshold.";
    otherwise
        text = "No recorded diagnostic provides a strong cause.";
end
end

function report = localEmptyReport(signals)
emptyUint32 = zeros(0, 1, "uint32");
emptyUint64 = zeros(0, 1, "uint64");
emptyDouble = zeros(0, 1);
emptyLogical = false(0, 1);
emptyString = strings(0, 1);
report = struct();
report.source = signals.source;
report.schema_version = signals.schema_version;
report.signal_names = signals.signal_names;
report.events = table( ...
    emptyUint32, emptyUint32, emptyUint32, ...
    emptyDouble, emptyDouble, emptyDouble, emptyDouble, ...
    emptyDouble, emptyDouble, emptyDouble, ...
    emptyLogical, emptyLogical, emptyLogical, ...
    emptyLogical, emptyLogical, emptyLogical, ...
    emptyLogical, emptyUint64, emptyLogical, emptyString, ...
    'VariableNames', { ...
    'start_index', 'end_index', 'sample_count', ...
    'start_time_s', 'end_time_s', 'duration_s', 'held_position_m', ...
    'position_jump_after_m', 'reference_change_m', 'peak_command_A', ...
    'raw_position_advanced', 'raw_position_held', ...
    'panasonic_wc_invalid', 'copley_wc_invalid', ...
    'panasonic_toggle_advanced', 'copley_toggle_advanced', ...
    'task_cycle_time_exceeded_seen', 'task_exceed_counter_delta', ...
    'task_exceed_correlated', 'cause'});
report.event_count = uint32(0);
report.longest_hold_s = 0;
report.velocity_endpoint_seen = false;
report.feedback_path_stale = false;
report.io_diagnostics_available = signals.io_diagnostics_available;
report.cause = "no_long_feedback_hold_detected";
report.primary_cause = report.cause;
report.interpretation = localInterpretation(report.cause);
report.summary = localSummary(strings(0, 1), false(0, 1), ...
    signals.task_cycle_time_exceeded, signals.task_exceed_counter);
end
