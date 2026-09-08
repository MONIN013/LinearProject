function result = run_commissioning_main(varargin)
%RUN_COMMISSIONING_MAIN Magnetic pole position estimation commissioning entry.
%
% Default execution is a fake-port dry run and never moves hardware.
% Real ADS execution requires a config, DryRun=false, and AllowRealMotion=true.

repoRoot = copley_project_root();

opts = localParseInputs(varargin{:});
[cfg, hasConfig] = localLoadConfig(opts);
cfg = localNormalizeConfig(cfg, hasConfig);
cfg = localApplySafetyGate(cfg, hasConfig, opts);
runtimePorts = localBuildRuntimePorts(cfg, hasConfig);
cfg = localResolveTaskPeriod(cfg, hasConfig, runtimePorts);
cfg = localResolveRuntimeZero(cfg, hasConfig, runtimePorts);
cfg = localApplyReferenceSeed(cfg, hasConfig);
[plan, cfg] = localPlan(cfg, hasConfig);
localPreflightRealMotion(cfg, hasConfig, plan, runtimePorts);
localApplyProvisionalCalibration(cfg, hasConfig, plan, opts, runtimePorts);

if opts.Verbose
    localPrintStart(hasConfig, cfg, plan, opts);
end

if hasConfig && ~isempty(runtimePorts)
    result = commissioning_run('Plan', plan, ...
        'MotorPort', runtimePorts.motorPort, ...
        'SequencerPort', runtimePorts.sequencerPort, ...
        'LoggerPort', runtimePorts.loggerPort, ...
        'RunStore', runtimePorts.runStore, ...
        'Clock', runtimePorts.clock, ...
        'ApplyCalibration', localShouldApplyCalibration(cfg, opts), ...
        'ApplyInterimCalibration', opts.ApplyInterimCalibration);
elseif hasConfig
    result = commissioning_run('Config', cfg, ...
        'ApplyCalibration', localShouldApplyCalibration(cfg, opts), ...
        'ApplyInterimCalibration', opts.ApplyInterimCalibration);
else
    result = commissioning_run('Plan', plan, ...
        'MotorPort', copley.testing.FakeMotorRuntimePort(), ...
        'SequencerPort', copley.testing.FakeSequencerPort(), ...
        'LoggerPort', copley.testing.FakeLoggerPort(), ...
        'RunStore', copley.testing.FakeRunStore(), ...
        'Clock', copley.testing.FakeClock(), ...
        'ApplyCalibration', localShouldApplyCalibration(cfg, opts), ...
        'ApplyInterimCalibration', opts.ApplyInterimCalibration);
end

if opts.Verbose
    localPrintResult(result);
end
end

function opts = localParseInputs(varargin)
p = inputParser;
addParameter(p, 'ConfigFile', '');
addParameter(p, 'Config', []);
addParameter(p, 'DryRun', true);
addParameter(p, 'AllowRealMotion', false);
addParameter(p, 'ApplyCalibration', []);
addParameter(p, 'ApplyInterimCalibration', true);
addParameter(p, 'SeedCalibration', []);
addParameter(p, 'Verbose', true);
parse(p, varargin{:});
opts = p.Results;
end

function [cfg, hasConfig] = localLoadConfig(opts)
cfg = opts.Config;
if isempty(cfg) && ~isempty(opts.ConfigFile)
    cfg = copley.infra.readJsonFile(opts.ConfigFile);
end
hasConfig = isstruct(cfg);
end

function cfg = localApplySafetyGate(cfg, hasConfig, opts)
if logical(opts.DryRun)
    if hasConfig
        cfg = localEnsureConnection(cfg);
        cfg.connection.dryRun = true;
    end
    return;
end

if ~hasConfig
    error('run_commissioning_main:RealMotionNeedsConfig', ...
        'Real ADS execution requires a config file or Config struct.');
end
if ~logical(opts.AllowRealMotion)
    error('run_commissioning_main:RealMotionNotAllowed', ...
        ['Refusing non-dry-run execution. Pass AllowRealMotion=true ' ...
         'only after TwinCAT mappings and the real-local config have been checked.']);
end

cfg = localEnsureConnection(cfg);
cfg.connection.dryRun = false;
end

function localPreflightRealMotion(cfg, hasConfig, plan, runtimePorts)
if ~hasConfig || localConnectionDryRun(cfg)
    return;
end
feedback = localReadMotorFeedback(cfg.connection, runtimePorts);
if ~isstruct(feedback)
    error('run_commissioning_main:MissingMotorFeedback', ...
        ['Could not read GVL_MotorRuntimeInternal.Feedback or ' ...
         'GVL_MotorRuntime.Status.']);
end
if isfield(feedback, 'fault') && logical(feedback.fault)
    error('run_commissioning_main:MotorRuntimeFault', ...
        'MotorRuntime reports fault_id=%u before protocol start.', ...
        uint32(localField(feedback, 'fault_id', 0)));
end
if ~isfield(feedback, 'encoder_position_raw')
    error('run_commissioning_main:MissingMotorFeedback', ...
        ['Could not read the encoder position from ' ...
         'MotorRuntime feedback/status.']);
end
xAbs_m = (double(feedback.encoder_position_raw) ...
    - double(int32(localField(plan, 'position_raw_zero', 0)))) ...
    * double(localField(plan, 'position_m_per_count', 1.0e-7)) ...
    + double(localField(plan, 'position_zero_m', 0.0));
xMin_m = double(localField(plan, 'x_soft_min_m', -Inf));
xMax_m = double(localField(plan, 'x_soft_max_m', Inf));
if xAbs_m < xMin_m || xAbs_m > xMax_m
    error('run_commissioning_main:StartOutsideSoftLimits', ...
        ['Current position %.12g m is outside configured soft limits ' ...
         '[%.12g, %.12g] m before protocol start.'], ...
        xAbs_m, xMin_m, xMax_m);
end
end

function apply = localShouldApplyCalibration(cfg, opts)
if ~isempty(opts.ApplyCalibration)
    apply = logical(opts.ApplyCalibration);
    return;
end
apply = true;
if isstruct(cfg) && ~localConnectionDryRun(cfg)
    apply = false;
end
end

function localApplyProvisionalCalibration(cfg, hasConfig, plan, opts, runtimePorts)
if ~hasConfig || localConnectionDryRun(cfg)
    return;
end
if ~isempty(opts.SeedCalibration) && ~logical(opts.SeedCalibration)
    return;
end

seed = struct( ...
    'theta_offset_hat_rad', double(localField(plan, ...
    'initial_theta_offset_guess_rad', 0.0)), ...
    'recommended_q_axis_sign', int16(localField(plan, 'q_axis_sign', 1)));
calibration = copley.domain.makeCalibrationRecord(plan, {seed}, 0.0);
calibration.metadata.accepted = false;

motorPort = runtimePorts.motorPort;
motorPort.stageReference(calibration);
pause(0.01);
feedback = motorPort.readStatus();
if isstruct(feedback) && isfield(feedback, 'fault') && logical(feedback.fault)
    error('run_commissioning_main:StagedReferenceFault', ...
        'MotorRuntime reports fault_id=%u after staging the reference.', ...
        uint32(feedback.fault_id));
end
end

function cfg = localNormalizeConfig(cfg, hasConfig)
if ~hasConfig
    return;
end
cfg = localEnsureConnection(cfg);
if isfield(cfg.connection, 'adsPort')
    if ~isfield(cfg.connection, 'sequencerAdsPort')
        cfg.connection.sequencerAdsPort = cfg.connection.adsPort;
    end
    if ~isfield(cfg.connection, 'motorAdsPort')
        cfg.connection.motorAdsPort = 852;
    end
    if ~isfield(cfg.connection, 'loggerAdsPort')
        cfg.connection.loggerAdsPort = 851;
    end
end
end

function cfg = localResolveRuntimeZero(cfg, hasConfig, runtimePorts)
if ~hasConfig
    return;
end

cfg = localEnsureParams(cfg);
if localConnectionDryRun(cfg)
    cfg.params.position_raw_zero = int32(0);
else
    feedback = localReadMotorFeedback(cfg.connection, runtimePorts);
    if ~isstruct(feedback) || ~isfield(feedback, 'encoder_position_raw')
        error('run_commissioning_main:MissingMotorFeedback', ...
            ['Could not read the encoder position from ' ...
             'MotorRuntime feedback/status.']);
    end
    cfg.params.position_raw_zero = int32(feedback.encoder_position_raw);
end
cfg.params.position_zero_m = 0.0;
if ~isfield(cfg, 'plan') || ~isstruct(cfg.plan)
    cfg.plan = struct();
end
cfg.plan.position_raw_zero = cfg.params.position_raw_zero;
cfg.plan.position_zero_m = cfg.params.position_zero_m;
if ~isfield(cfg, 'runtime') || ~isstruct(cfg.runtime)
    cfg.runtime = struct();
end
cfg.runtime.position_raw_zero = cfg.params.position_raw_zero;
cfg.runtime.position_zero_m = cfg.params.position_zero_m;
end

function cfg = localResolveTaskPeriod(cfg, hasConfig, runtimePorts)
if ~hasConfig || isempty(runtimePorts)
    return;
end

taskPeriod_s = runtimePorts.sequencerPort.readTaskPeriod_s();
supportedPeriods_s = [1.0 / 4000.0, 1.0 / 8000.0];
if min(abs(taskPeriod_s - supportedPeriods_s)) > 1.0e-12
    error('copley:run_commissioning_main:UnsupportedTaskPeriod', ...
        'PLC task period %.12g s is not a supported 4 or 8 kHz setting.', ...
        taskPeriod_s);
end

cfg = localEnsureParams(cfg);
cfg.params.task_period_s = taskPeriod_s;
if ~isfield(cfg, 'runtime') || ~isstruct(cfg.runtime)
    cfg.runtime = struct();
end
cfg.runtime.task_period_s = taskPeriod_s;
end

function cfg = localApplyReferenceSeed(cfg, hasConfig)
if ~hasConfig || ~isfield(cfg, 'reference') || ~isstruct(cfg.reference)
    return;
end
if ~isfield(cfg.reference, 'theta_offset_hat_rad')
    return;
end

cfg = localEnsureParams(cfg);
cfg.params.initial_theta_offset_guess_rad = ...
    double(cfg.reference.theta_offset_hat_rad);
if isfield(cfg.reference, 'q_axis_sign')
    cfg.params.q_axis_sign = int16(cfg.reference.q_axis_sign);
end
end

function ports = localBuildRuntimePorts(cfg, hasConfig)
ports = [];
if ~hasConfig || localConnectionDryRun(cfg)
    return;
end

conn = cfg.connection;
cacheKey = localRuntimePortCacheKey(conn);
persistent cachedKey cachedPorts
if ~isempty(cachedPorts) && isequal(cachedKey, cacheKey)
    ports = cachedPorts;
    return;
end

seqCfg = localPortConfig(conn, localField(conn, 'sequencerAdsPort', 851));
motorCfg = localPortConfig(conn, localField(conn, 'motorAdsPort', 852));
loggerCfg = localPortConfig(conn, localField(conn, 'loggerAdsPort', 851));

seqClient = copley.infra.AdsClient(seqCfg);
motorCfg.sharedAds = seqClient.Ads;

ports = struct();
ports.sequencerPort = copley.infra.AdsSequencerPort( ...
    seqClient, seqCfg);
ports.motorPort = copley.infra.AdsMotorRuntimePort( ...
    copley.infra.AdsClient(motorCfg));
if localField(conn, 'skipLogDownload', false)
    ports.loggerPort = copley.testing.FakeLoggerPort();
else
    loggerCfg.sharedAds = seqClient.Ads;
    ports.loggerPort = copley.infra.AdsLoggerPort( ...
        copley.infra.AdsClient(loggerCfg));
end
ports.runStore = copley.infra.FileRunStore( ...
    localField(cfg, 'baseDir', fullfile('data', 'commissioning')));
ports.clock = copley.infra.SystemClock();
cachedKey = cacheKey;
cachedPorts = ports;
end

function key = localRuntimePortCacheKey(conn)
key = sprintf('%s|%u|%u|%u|%u', ...
    char(localField(conn, 'amsNetId', 'Local')), ...
    uint32(localField(conn, 'sequencerAdsPort', localField(conn, 'adsPort', 851))), ...
    uint32(localField(conn, 'motorAdsPort', 852)), ...
    uint32(localField(conn, 'loggerAdsPort', 851)), ...
    uint32(logical(localField(conn, 'skipLogDownload', false))));
end

function cfg = localPortConfig(conn, adsPort)
cfg = conn;
cfg.adsPort = adsPort;
cfg.dryRun = false;
end

function feedback = localReadMotorFeedback(conn, runtimePorts)
if nargin >= 2 && isstruct(runtimePorts) ...
        && isfield(runtimePorts, 'motorPort') && ~isempty(runtimePorts.motorPort)
    feedback = runtimePorts.motorPort.readStatus();
    return;
end
motorCfg = conn;
if isfield(conn, 'motorAdsPort')
    motorCfg.adsPort = conn.motorAdsPort;
else
    motorCfg.adsPort = 852;
end
motorCfg.dryRun = false;
port = copley.infra.AdsMotorRuntimePort(copley.infra.AdsClient(motorCfg));
feedback = port.readStatus();
end

function tf = localConnectionDryRun(cfg)
tf = true;
if isfield(cfg, 'connection') && isstruct(cfg.connection) ...
        && isfield(cfg.connection, 'dryRun')
    tf = logical(cfg.connection.dryRun);
end
end

function cfg = localEnsureParams(cfg)
if ~isfield(cfg, 'params') || ~isstruct(cfg.params)
    cfg.params = struct();
end
end

function [plan, cfg] = localPlan(cfg, hasConfig)
plan = copley.domain.defaultExperimentPlan();
if hasConfig
    if isfield(cfg, 'plan') && isstruct(cfg.plan)
        plan = localMerge(plan, cfg.plan);
    end
    if isfield(cfg, 'params') && isstruct(cfg.params)
        plan = localMerge(plan, cfg.params);
    end
    if isfield(cfg, 'runtime') && isstruct(cfg.runtime)
        plan = localMerge(plan, cfg.runtime);
    end
    if isfield(cfg, 'analysis') && isstruct(cfg.analysis)
        if ~isfield(plan, 'analysis') || ~isstruct(plan.analysis)
            plan.analysis = struct();
        end
        plan.analysis = localMerge(plan.analysis, cfg.analysis);
    end
end
end

function cfg = localEnsureConnection(cfg)
if ~isfield(cfg, 'connection') || ~isstruct(cfg.connection)
    cfg.connection = struct();
end
end

function out = localMerge(out, in)
names = fieldnames(in);
for k = 1:numel(names)
    out.(names{k}) = in.(names{k});
end
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end

function localPrintStart(hasConfig, cfg, plan, opts)
fprintf('Magnetic pole position estimation commissioning\n');
fprintf('Lease ID: %u\n', uint32(plan.lease_id));
if hasConfig
    dryRun = true;
    if isfield(cfg, 'connection') && isstruct(cfg.connection) ...
            && isfield(cfg.connection, 'dryRun')
        dryRun = logical(cfg.connection.dryRun);
    end
    fprintf('Mode: ADS ports, dryRun=%d\n', dryRun);
else
    fprintf('Mode: fake ports, dryRun=1\n');
end
if ~logical(opts.DryRun)
    fprintf('Real motion gate: AllowRealMotion=%d\n', logical(opts.AllowRealMotion));
end
end

function localPrintResult(result)
fprintf('Accepted: %d\n', logical(result.accepted));
fprintf('Reference registered: %d\n', logical(result.calibration_applied));
if isfield(result, 'calibration') && isstruct(result.calibration)
    cal = copley.domain.normalizeCalibrationRecord(result.calibration);
    fprintf('reference_position_count: %d\n', ...
        int32(cal.reference_position_count));
    fprintf('reference_commutation_angle: %u\n', ...
        uint16(cal.reference_commutation_angle));
end
end
