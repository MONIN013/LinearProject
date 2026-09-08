function T = toSampleTable(rawLog, plan, protocolId)
%TOSAMPLETABLE Normalize logger output to the analysis table schema.
if nargin < 2 || isempty(plan)
    plan = copley.domain.defaultExperimentPlan(uint32(1));
end
if nargin < 3
    protocolId = [];
end

T = localRawToTable(rawLog);
if ~isempty(protocolId)
    if ~ismember('protocol_id', T.Properties.VariableNames)
        T.protocol_id = repmat(uint16(protocolId), height(T), 1);
    end
    T = T(uint16(T.protocol_id) == uint16(protocolId), :);
end

if isempty(T) || height(T) == 0
    return;
end

T = localEnsureColumn(T, 'sample_index', (0:height(T)-1)');
T = localEnsureColumn(T, 'phase_id', zeros(height(T), 1, 'uint16'));
T = localEnsureColumn(T, 'angle_index', zeros(height(T), 1, 'uint16'));
T = localEnsureColumn(T, 'protocol2_local_sample_index', T.sample_index);
T = localEnsureColumn(T, 'experiment_angle_rad', zeros(height(T), 1));

if ~ismember('t_s', T.Properties.VariableNames)
    if ismember('sequence_t_s', T.Properties.VariableNames)
        T.t_s = double(T.sequence_t_s);
    elseif ismember('protocol_t_s', T.Properties.VariableNames)
        T.t_s = double(T.protocol_t_s);
    elseif ismember('t_cycle_s', T.Properties.VariableNames)
        T.t_s = double(T.t_cycle_s);
    else
        T.t_s = double(T.sample_index - T.sample_index(1)) .* localField(plan, 'task_period_s', 0.000125);
    end
end
if ~ismember('protocol_t_s', T.Properties.VariableNames)
    T.protocol_t_s = double(T.t_s - T.t_s(1));
end

if ~ismember('x_abs_m', T.Properties.VariableNames)
    positionRaw = localFeedbackColumn(T, ...
        'encoder_position_raw', 'panasonic_position_raw');
    if ~isempty(positionRaw)
        rawZero = double(localField(plan, 'position_raw_zero', 0));
        zeroM = double(localField(plan, 'position_zero_m', 0.0));
        scale = double(localField(plan, 'position_m_per_count', 1.0e-7));
        T.x_abs_m = zeroM + (double(positionRaw) - rawZero) .* scale;
    else
        T.x_abs_m = zeros(height(T), 1);
    end
end

if ~ismember('v_actual_mps', T.Properties.VariableNames)
    velocityRaw = localFeedbackColumn(T, ...
        'encoder_velocity_raw', 'panasonic_velocity_raw');
    if ~isempty(velocityRaw)
        T.v_actual_mps = double(velocityRaw) .* ...
            double(localField(plan, 'velocity_mps_per_count', 1.0e-6));
    else
        T.v_actual_mps = localEstimatedVelocity(T.x_abs_m, T.t_s);
    end
end
if ~ismember('v_est_mps', T.Properties.VariableNames)
    T.v_est_mps = localEstimatedVelocity(T.x_abs_m, T.t_s);
end

if ismember('iq_cmd_count_req_lreal', T.Properties.VariableNames)
    T.iq_cmd_count_req_lreal = double(T.iq_cmd_count_req_lreal);
    T.iq_cmd_count_req_lreal_from_log = isfinite(T.iq_cmd_count_req_lreal);
else
    if ismember('iq_cmd_count_req', T.Properties.VariableNames)
        T.iq_cmd_count_req_lreal = double(T.iq_cmd_count_req);
    elseif ismember('target_current_count', T.Properties.VariableNames)
        T.iq_cmd_count_req_lreal = double(T.target_current_count);
    else
        T.iq_cmd_count_req_lreal = zeros(height(T), 1);
    end
    T.iq_cmd_count_req_lreal_from_log = false(height(T), 1);
end
if ismember('iq_cmd_count_req', T.Properties.VariableNames)
    iqFallback = double(T.iq_cmd_count_req);
else
    iqFallback = zeros(height(T), 1);
end
T.iq_cmd_count_req_lreal(~T.iq_cmd_count_req_lreal_from_log) = ...
    iqFallback(~T.iq_cmd_count_req_lreal_from_log);
T.iq_cmd_count_req = int16(T.iq_cmd_count_req_lreal);

if ismember('target_current_count_lreal', T.Properties.VariableNames)
    T.target_current_count_lreal = double(T.target_current_count_lreal);
    T.target_current_count_lreal_from_log = isfinite(T.target_current_count_lreal);
else
    if ismember('target_current_count', T.Properties.VariableNames)
        T.target_current_count_lreal = double(T.target_current_count);
    elseif ismember('output_torque_count', T.Properties.VariableNames)
        T.target_current_count_lreal = double(T.output_torque_count);
    else
        T.target_current_count_lreal = T.iq_cmd_count_req_lreal;
    end
    T.target_current_count_lreal_from_log = false(height(T), 1);
end
if ismember('target_current_count', T.Properties.VariableNames)
    targetFallback = double(T.target_current_count);
elseif ismember('output_torque_count', T.Properties.VariableNames)
    targetFallback = double(T.output_torque_count);
else
    targetFallback = T.iq_cmd_count_req_lreal;
end
T.target_current_count_lreal(~T.target_current_count_lreal_from_log) = ...
    targetFallback(~T.target_current_count_lreal_from_log);
T.target_current_count = int16(T.target_current_count_lreal);

if ~ismember('output_torque_count', T.Properties.VariableNames)
    T.output_torque_count = int16(T.target_current_count);
end
if ~ismember('actual_current_count', T.Properties.VariableNames)
    if ismember('copley_actual_current_count', T.Properties.VariableNames)
        T.actual_current_count = int16(T.copley_actual_current_count);
    else
        T.actual_current_count = zeros(height(T), 1, 'int16');
    end
end

targetAperCount = double(localField(plan, 'target_torque_A_per_1000', 0.1)) / 1000.0;
actualAperCount = double(localField(plan, 'actual_current_A_per_1000', 0.1)) / 1000.0;
T.iq_cmd_raw_A = double(T.iq_cmd_count_req_lreal) .* targetAperCount;
T.iq_cmd_A = double(T.target_current_count_lreal) .* targetAperCount;
T.target_current_A = double(T.target_current_count_lreal) .* targetAperCount;
T.output_torque_A = double(T.output_torque_count) .* targetAperCount;
T.actual_current_A = double(T.actual_current_count) .* actualAperCount;
end

function T = localRawToTable(rawLog)
if istable(rawLog)
    T = rawLog;
    return;
end
if isstruct(rawLog) && isfield(rawLog, 'rawTable') && istable(rawLog.rawTable)
    T = rawLog.rawTable;
    return;
end
if isstruct(rawLog) && isfield(rawLog, 'samples') && isstruct(rawLog.samples)
    T = localRawToTable(rawLog.samples);
    if isfield(rawLog, 'protocol_id') && ~ismember('protocol_id', T.Properties.VariableNames)
        T.protocol_id = repmat(uint16(rawLog.protocol_id), height(T), 1);
    end
    return;
end

if ~isstruct(rawLog)
    T = table();
    return;
end

names = fieldnames(rawLog);
n = 0;
for k = 1:numel(names)
    value = rawLog.(names{k});
    if isnumeric(value) || islogical(value)
        n = max(n, numel(value));
    end
end
if n <= 1
    T = table();
    return;
end

T = table();
for k = 1:numel(names)
    name = names{k};
    value = rawLog.(name);
    if isnumeric(value) || islogical(value)
        if numel(value) == n
            T.(name) = localColumn(value);
        elseif isscalar(value)
            T.(name) = repmat(value, n, 1);
        end
    end
end
end

function T = localEnsureColumn(T, name, defaultValue)
if ismember(name, T.Properties.VariableNames)
    T.(name) = localColumn(T.(name));
else
    T.(name) = localColumn(defaultValue);
end
end

function y = localColumn(x)
y = x(:);
end

function v = localEstimatedVelocity(x, t)
x = double(x(:));
t = double(t(:));
if numel(x) < 2
    v = zeros(size(x));
    return;
end
dt = [diff(t); median(diff(t))];
dt(~isfinite(dt) | dt <= 0) = median(dt(isfinite(dt) & dt > 0));
if isempty(dt) || ~all(isfinite(dt))
    dt = ones(size(x)) .* 0.000125;
end
v = [0; diff(x)] ./ [dt(1); dt(1:end-1)];
v(~isfinite(v)) = 0;
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end

function value = localFeedbackColumn(T, currentName, legacyName)
value = [];
if ismember(currentName, T.Properties.VariableNames)
    value = T.(currentName);
elseif ismember(legacyName, T.Properties.VariableNames)
    value = T.(legacyName);
end
end
