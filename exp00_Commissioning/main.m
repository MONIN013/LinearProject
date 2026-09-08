% Magnetic pole position estimation real replay entry point.
%
% Edit defaultConfigFile to change the replay target. This script defaults to
% the accepted 2026-06-17 sequence and intentionally skips the final RETAIN
% calibration write; interim calibration remains enabled for the sequence.

repoRoot = copley_project_root();

defaultConfigFile = localEnvOrDefault('COPLEY_MAIN_CONFIG', ...
    fullfile(repoRoot, 'config', 'copley', ...
    'exp_20260617_164644_sequence.real.local.json'));
cfg = copley.infra.readJsonFile(defaultConfigFile);
applyInterimCalibration = localEnvLogical( ...
    'COPLEY_MAIN_APPLY_INTERIM_CALIBRATION', true);

result = run_commissioning_main( ...
    'Config', cfg, ...
    'DryRun', false, ...
    'AllowRealMotion', true, ...
    'ApplyCalibration', false, ...
    'ApplyInterimCalibration', applyInterimCalibration, ...
    'Verbose', true);

theta = copley.analysis.buildThetaResult(result);
if isfield(result, 'output_dir') && ~isempty(result.output_dir)
    fprintf('Run output: %s\n', result.output_dir);
end
fprintf('Estimated theta_offset_rad: %.12g\n', double(theta.theta_offset_hat_rad));
fprintf('Estimated theta_offset_deg: %.12g\n', double(theta.theta_offset_hat_deg));
fprintf('reference_position_count: %d\n', ...
    int32(theta.reference_position_count));
fprintf('reference_commutation_angle: %u count / %.12g deg\n', ...
    uint16(theta.reference_commutation_angle), ...
    double(theta.reference_commutation_angle_deg));

function value = localEnvOrDefault(name, defaultValue)
value = getenv(name);
if isempty(value)
    value = defaultValue;
end
end

function tf = localEnvLogical(name, defaultValue)
value = getenv(name);
if isempty(value)
    tf = logical(defaultValue);
    return;
end
tf = any(strcmpi(value, {'1', 'true', 'yes', 'on'}));
end
