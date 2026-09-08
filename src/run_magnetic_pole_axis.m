function result = run_magnetic_pole_axis(targetAxisIndex)
%RUN_MAGNETIC_POLE_AXIS Estimate one magnetic pole position and write it.

axisIndex = localValidateAxisIndex(targetAxisIndex);
repoRoot = copley_project_root();

cfg = copley.infra.readJsonFile(localConfigFile(repoRoot));
cfg = localConfigForAxis(cfg, axisIndex);

result = run_commissioning_main( ...
    'Config', cfg, ...
    'DryRun', false, ...
    'AllowRealMotion', true, ...
    'ApplyCalibration', true, ...
    'ApplyInterimCalibration', true, ...
    'SeedCalibration', true, ...
    'Verbose', false);
end

function axisIndex = localValidateAxisIndex(targetAxisIndex)
if ~isnumeric(targetAxisIndex) || ~isscalar(targetAxisIndex) ...
        || ~ismember(double(targetAxisIndex), [1 2 3 4])
    error('run_magnetic_pole_axis:InvalidAxisIndex', ...
        'targetAxisIndex must be from 1 through 4.');
end
axisIndex = uint16(targetAxisIndex);
end

function configFile = localConfigFile(repoRoot)
configFile = getenv('COPLEY_MAGNETIC_POLE_CONFIG');
if isempty(configFile)
    configFile = fullfile(repoRoot, 'config', 'copley', ...
        'exp_20260617_164644_sequence.real.local.json');
end
end

function cfg = localConfigForAxis(cfg, axisIndex)
cfg = localEnsureStructField(cfg, 'plan');
cfg = localEnsureStructField(cfg, 'params');
cfg.plan.axis_index = axisIndex;
cfg.params.axis_index = axisIndex;
cfg = localRemovePreviousAxisReference(cfg);
end

function cfg = localEnsureStructField(cfg, fieldName)
if ~isfield(cfg, fieldName) || ~isstruct(cfg.(fieldName))
    cfg.(fieldName) = struct();
end
end

function cfg = localRemovePreviousAxisReference(cfg)
if isfield(cfg, 'reference')
    cfg = rmfield(cfg, 'reference');
end
if isfield(cfg, 'analysis') && isstruct(cfg.analysis) ...
        && isfield(cfg.analysis, 'protocol1_theta_reference_rad')
    cfg.analysis = rmfield(cfg.analysis, 'protocol1_theta_reference_rad');
end
end
