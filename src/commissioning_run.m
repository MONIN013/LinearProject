function out = commissioning_run(varargin)
%COMMISSIONING_RUN Run commissioning with staged and registered references.
% No config/ports means fake ports, so this default never moves hardware.
copley_project_root();

p = inputParser;
addParameter(p, 'ConfigFile', '');
addParameter(p, 'Config', []);
addParameter(p, 'Plan', []);
addParameter(p, 'MotorPort', []);
addParameter(p, 'SequencerPort', []);
addParameter(p, 'LoggerPort', []);
addParameter(p, 'RunStore', []);
addParameter(p, 'Clock', []);
addParameter(p, 'ApplyCalibration', true);
addParameter(p, 'ApplyInterimCalibration', true);
parse(p, varargin{:});
opts = p.Results;

cfg = opts.Config;
if isempty(cfg) && ~isempty(opts.ConfigFile)
    cfg = copley.infra.readJsonFile(opts.ConfigFile);
end

plan = opts.Plan;
if isempty(plan)
    plan = copley.domain.defaultExperimentPlan();
    plan = localApplyConfig(plan, cfg);
end

motorPort = opts.MotorPort;
sequencerPort = opts.SequencerPort;
loggerPort = opts.LoggerPort;
runStore = opts.RunStore;
clock = opts.Clock;

if isempty(motorPort) || isempty(sequencerPort) || isempty(loggerPort) ...
        || isempty(runStore) || isempty(clock)
    if isempty(cfg)
        warning('commissioning_run:UsingFakePorts', ...
            'No config or real ports were supplied. Running with fake ports.');
        motorPort = copley.testing.FakeMotorRuntimePort();
        sequencerPort = copley.testing.FakeSequencerPort();
        loggerPort = copley.testing.FakeLoggerPort();
        runStore = copley.testing.FakeRunStore();
        clock = copley.testing.FakeClock();
    else
        [motorPort, sequencerPort, loggerPort, runStore, clock] = localBuildPorts(cfg);
    end
end

useCase = copley.app.CommissioningUseCase( ...
    motorPort, sequencerPort, loggerPort, runStore, clock, [], ...
    opts.ApplyCalibration, opts.ApplyInterimCalibration);
out = useCase.run(plan);
end

function [motorPort, sequencerPort, loggerPort, runStore, clock] = localBuildPorts(cfg)
conn = localField(cfg, 'connection', struct());
if localField(conn, 'dryRun', true)
    motorPort = copley.testing.FakeMotorRuntimePort();
    sequencerPort = copley.testing.FakeSequencerPort();
    loggerPort = copley.testing.FakeLoggerPort();
    runStore = copley.testing.FakeRunStore();
    clock = copley.testing.FakeClock();
    return;
end
seqCfg = localPortConfig(conn, localField(conn, 'sequencerAdsPort', 851));
motorCfg = localPortConfig(conn, localField(conn, 'motorAdsPort', 852));
loggerCfg = localPortConfig(conn, localField(conn, 'loggerAdsPort', 851));

seqClient = copley.infra.AdsClient(seqCfg);
motorCfg.sharedAds = seqClient.Ads;

sequencerPort = copley.infra.AdsSequencerPort(seqClient, seqCfg);
motorPort = copley.infra.AdsMotorRuntimePort(copley.infra.AdsClient(motorCfg));
if localField(conn, 'skipLogDownload', false)
    loggerPort = copley.testing.FakeLoggerPort();
else
    loggerCfg.sharedAds = seqClient.Ads;
    loggerPort = copley.infra.AdsLoggerPort(copley.infra.AdsClient(loggerCfg));
end
runStore = copley.infra.FileRunStore( ...
    localField(cfg, 'baseDir', fullfile('data', 'commissioning')));
clock = copley.infra.SystemClock();
end

function cfg = localPortConfig(conn, adsPort)
cfg = conn;
cfg.adsPort = adsPort;
if ~isfield(cfg, 'dryRun')
    cfg.dryRun = true;
end
end

function plan = localApplyConfig(plan, cfg)
if ~isstruct(cfg)
    return;
end
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
