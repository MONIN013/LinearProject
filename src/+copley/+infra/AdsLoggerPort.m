classdef AdsLoggerPort < copley.ports.LoggerPort
    properties
        Client
        BufferSymbol = 'GVL_ExperimentLogger.buffer'
        SampleCountSymbol = 'GVL_ExperimentLogger.sampleCount'
        OverflowSymbol = 'GVL_ExperimentLogger.overflow'
    end

    methods
        function obj = AdsLoggerPort(client)
            obj.Client = client;
        end

        function rawLog = downloadProtocol(obj, protocolId, varargin)
            if obj.Client.DryRun
                rawLog = struct('protocol_id', uint16(protocolId), 'accepted', true);
                return;
            end
            if localConfigField(obj.Client.Config, 'skipLogDownload', false)
                rawLog = struct('protocol_id', uint16(protocolId), ...
                    'synthetic', true, 'accepted', true, ...
                    'reason', 'real protocol completed; log download skipped');
                return;
            end
            plan = [];
            if ~isempty(varargin)
                plan = varargin{1};
            end
            sampleCount = obj.Client.readSymbol(obj.SampleCountSymbol);
            overflow = obj.Client.readSymbol(obj.OverflowSymbol);
            rawLog = struct();
            rawLog.protocol_id = uint16(protocolId);
            rawLog.sample_count = uint32(sampleCount);
            rawLog.overflow = logical(overflow);
            if localConfigField(obj.Client.Config, 'sparseLogDownload', false)
                indices = localSparseIndices(double(sampleCount), uint16(protocolId), plan);
                rawLog.download_mode = 'sparse_plan_indices';
            else
                indices = 0:(double(sampleCount) - 1);
                rawLog.download_mode = 'full';
            end
            rawLog.downloaded_sample_count = uint32(numel(indices));
            [rawLog.samples, rawLog.read_strategy] = ...
                localReadSamples(obj.Client, obj.BufferSymbol, indices);
        end
    end
end

function [samples, readStrategy] = localReadSamples(client, bufferSymbol, indices)
if isempty(indices)
    samples = [];
    readStrategy = 'empty';
    return;
end
if localIsZeroBasedContiguous(indices)
    try
        samples = localReadContiguousSamples(client, bufferSymbol, numel(indices));
        readStrategy = 'bulk';
        return;
    catch
        % Fall back to per-sample reads for ADS runtimes that reject partial array reads.
    end
end
sampleBytes = localLoggerSampleBytes();
count = numel(indices);
buffer = zeros(sampleBytes, count, 'uint8');
for i = 1:count
    symbol = sprintf('%s[%u]', bufferSymbol, uint32(indices(i)));
    one = client.readSymbol(symbol);
    if ~isa(one, 'uint8') || ~ismember(numel(one), localSupportedLoggerSampleBytes())
        error('copley:AdsLoggerPort:SampleReadFailed', ...
            'Unexpected logger sample payload at %s.', symbol);
    end
    one = uint8(one(:));
    buffer(1:numel(one), i) = one;
    if numel(one) < sampleBytes
        buffer(numel(one)+1:sampleBytes, i) = localNanPadding(sampleBytes - numel(one));
    end
end
samples = localParseLoggerSamples(buffer(:), count);
readStrategy = 'per_sample';
end

function tf = localIsZeroBasedContiguous(indices)
indices = double(indices(:)');
tf = ~isempty(indices) && indices(1) == 0 ...
    && all(diff(indices) == 1);
end

function samples = localReadContiguousSamples(client, bufferSymbol, sampleCount)
sampleBytes = localLoggerSampleBytes();
rawBytes = client.readSymbolBytes(bufferSymbol, sampleBytes * double(sampleCount));
if numel(rawBytes) < sampleBytes * double(sampleCount)
    error('copley:AdsLoggerPort:BulkReadShort', ...
        'Bulk logger read returned %u bytes for %u samples.', ...
        uint32(numel(rawBytes)), uint32(sampleCount));
end
samples = localParseLoggerSamples(rawBytes(:), sampleCount);
end

function indices = localSparseIndices(sampleCount, protocolId, plan)
if sampleCount <= 0
    indices = [];
    return;
end
if ~isstruct(plan)
    indices = 0:(sampleCount - 1);
    return;
end

taskPeriod_s = max(double(localField(plan, 'task_period_s', 0.000125)), eps);
switch double(protocolId)
    case 1
        times = localProtocol1Times(plan);
    case 2
        times = localProtocol2Times(plan);
    case 3
        times = localProtocol3Times(plan);
    otherwise
        times = [];
end

indices = localTimesToIndices(times, taskPeriod_s, sampleCount);
if isempty(indices)
    indices = 0:(sampleCount - 1);
end
end

function indices = localTimesToIndices(times, taskPeriod_s, sampleCount)
indices = unique(round(double(times(:)) ./ taskPeriod_s))';
indices = indices(isfinite(indices));
indices = indices(indices >= 0 & indices < sampleCount);
indices = double(indices);
end

function times = localProtocol1Times(plan)
taskPeriod_s = max(double(localField(plan, 'task_period_s', 0.000125)), eps);
settle_s = localProtocolField(plan, 1, 'settle_time_s', 0.05);
pulse_s = localProtocolField(plan, 1, 'pulse_time_s', 0.05);
post_s = localProtocolField(plan, 1, 'post_time_s', 0.05);
angleCount = max(1, round(localProtocolField(plan, 1, 'angle_count', 12)));
cycle_s = 2.0 * settle_s + 2.0 * pulse_s + post_s;
times = [];
for angle = 0:(angleCount - 1)
    base_s = double(angle) * cycle_s;
    positiveStart_s = base_s + settle_s;
    oppositeStart_s = base_s + settle_s + pulse_s + settle_s;
    times = [times, ...
        positiveStart_s + [taskPeriod_s, max(taskPeriod_s, pulse_s - taskPeriod_s)], ...
        oppositeStart_s + [taskPeriod_s, max(taskPeriod_s, pulse_s - taskPeriod_s)]]; %#ok<AGROW>
end
end

function times = localProtocol2Times(plan)
taskPeriod_s = max(double(localField(plan, 'task_period_s', 0.000125)), eps);
accel_s = localField(plan, 'protocol2_accel_time_s', 0.050);
const_s = localField(plan, 'protocol2_const_time_s', 0.0);
pause_s = localField(plan, 'protocol2_pause_time_s', 0.050);
angleDuration_s = 4.0 * accel_s + 2.0 * const_s + 2.0 * pause_s;
edge_s = localAnalysisField(plan, 'protocol2_edge_discard_s', 0.002);
pairCount = max(8, round(localAnalysisField(plan, ...
    'protocol2_sparse_pair_count', 12)));
start_s = edge_s + taskPeriod_s;
stop_s = angleDuration_s - edge_s - taskPeriod_s;
if stop_s <= start_s
    localTimes = angleDuration_s ./ 2.0;
else
    localTimes = linspace(start_s, stop_s, pairCount);
end
times = [localTimes, angleDuration_s + localTimes + 2.0 * taskPeriod_s];
end

function times = localProtocol3Times(plan)
taskPeriod_s = max(double(localField(plan, 'task_period_s', 0.000125)), eps);
settle_s = localProtocolField(plan, 3, 'settle_time_s', 0.05);
pulse_s = localProtocolField(plan, 3, 'pulse_time_s', 0.05);
post_s = localProtocolField(plan, 3, 'post_time_s', 0.05); %#ok<NASGU>
positiveStart_s = settle_s;
negativeStart_s = settle_s + pulse_s + settle_s;
times = [positiveStart_s + [taskPeriod_s, max(taskPeriod_s, pulse_s - taskPeriod_s)], ...
    negativeStart_s + [taskPeriod_s, max(taskPeriod_s, pulse_s - taskPeriod_s)]];
end

function samples = localParseLoggerSamples(buffer, sampleCount)
sampleBytes = localLoggerSampleBytes();
if numel(buffer) < sampleBytes * double(sampleCount)
    sampleBytes = localInferLoggerSampleBytes(numel(buffer), sampleCount);
end
available = floor(double(numel(buffer)) / sampleBytes);
count = min(double(sampleCount), available);
buffer = uint8(buffer(:));

samples = struct();
samples.sample_index = zeros(count, 1, 'uint32');
samples.protocol_id = zeros(count, 1, 'uint16');
samples.phase_id = zeros(count, 1, 'uint16');
samples.angle_index = zeros(count, 1, 'uint16');
samples.protocol2_local_sample_index = zeros(count, 1, 'uint16');
samples.t_cycle_s = zeros(count, 1);
samples.experiment_angle_rad = zeros(count, 1);
samples.x_ref_traj_m = zeros(count, 1);
samples.encoder_position_raw = zeros(count, 1, 'int32');
samples.encoder_velocity_raw = zeros(count, 1, 'int32');
samples.copley_actual_current_count = zeros(count, 1, 'int16');
samples.output_torque_count = zeros(count, 1, 'int16');
samples.fault_id = zeros(count, 1, 'uint32');
samples.iq_cmd_count_req_lreal = zeros(count, 1);
samples.target_current_count_lreal = zeros(count, 1);

for i = 1:count
    base = (i - 1) * sampleBytes;
    samples.sample_index(i) = localGetUint32(buffer, base + 1);
    samples.protocol_id(i) = localGetUint16(buffer, base + 5);
    samples.phase_id(i) = localGetUint16(buffer, base + 7);
    samples.angle_index(i) = localGetUint16(buffer, base + 9);
    samples.protocol2_local_sample_index(i) = localGetUint16(buffer, base + 11);
    samples.t_cycle_s(i) = localGetDouble(buffer, base + 17);
    samples.experiment_angle_rad(i) = localGetDouble(buffer, base + 25);
    samples.x_ref_traj_m(i) = localGetDouble(buffer, base + 33);
    samples.encoder_position_raw(i) = localGetInt32(buffer, base + 41);
    samples.encoder_velocity_raw(i) = localGetInt32(buffer, base + 45);
    samples.copley_actual_current_count(i) = localGetInt16(buffer, base + 49);
    samples.output_torque_count(i) = localGetInt16(buffer, base + 51);
    samples.fault_id(i) = localGetUint32(buffer, base + 53);
    samples.iq_cmd_count_req_lreal(i) = localGetDouble(buffer, base + 57);
    samples.target_current_count_lreal(i) = localGetDouble(buffer, base + 65);
end
end

function bytes = localLoggerSampleBytes()
bytes = 72;
end

function bytes = localSupportedLoggerSampleBytes()
bytes = localLoggerSampleBytes();
end

function bytes = localInferLoggerSampleBytes(bufferBytes, sampleCount)
bytes = localLoggerSampleBytes();
supported = localSupportedLoggerSampleBytes();
for k = numel(supported):-1:1
    candidate = supported(k);
    if bufferBytes >= candidate * double(sampleCount)
        bytes = candidate;
        return;
    end
end
end

function bytes = localNanPadding(byteCount)
bytes = zeros(byteCount, 1, 'uint8');
nanBytes = typecast(NaN, 'uint8');
pos = 1;
while pos <= byteCount
    n = min(numel(nanBytes), byteCount - pos + 1);
    bytes(pos:pos+n-1) = nanBytes(1:n);
    pos = pos + n;
end
end

function value = localGetUint16(bytes, pos)
value = typecast(uint8(bytes(pos:pos+1)), 'uint16');
end

function value = localGetInt16(bytes, pos)
value = typecast(uint8(bytes(pos:pos+1)), 'int16');
end

function value = localGetUint32(bytes, pos)
value = typecast(uint8(bytes(pos:pos+3)), 'uint32');
end

function value = localGetInt32(bytes, pos)
value = typecast(uint8(bytes(pos:pos+3)), 'int32');
end

function value = localGetDouble(bytes, pos)
value = typecast(uint8(bytes(pos:pos+7)), 'double');
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
value = double(value);
end

function value = localProtocolField(plan, protocolId, fieldName, defaultValue)
value = defaultValue;
if isstruct(plan) && isfield(plan, fieldName)
    value = plan.(fieldName);
end
key = sprintf('protocol%d', double(protocolId));
if isstruct(plan) && isfield(plan, key)
    p = plan.(key);
    if isstruct(p) && isfield(p, fieldName)
        value = p.(fieldName);
    end
end
value = double(value);
end

function value = localAnalysisField(plan, name, defaultValue)
value = defaultValue;
if isstruct(plan) && isfield(plan, 'analysis') && isstruct(plan.analysis) ...
        && isfield(plan.analysis, name)
    value = plan.analysis.(name);
elseif isstruct(plan) && isfield(plan, name)
    value = plan.(name);
end
value = double(value);
end

function value = localConfigField(config, name, defaultValue)
value = defaultValue;
if isstruct(config) && isfield(config, name)
    value = config.(name);
end
end
