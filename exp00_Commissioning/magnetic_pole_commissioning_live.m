% Magnetic-pole commissioning entry point with persisted analysis artifacts.
targetAxisIndex = uint16(4);

result = run_magnetic_pole_axis(targetAxisIndex);
if isfield(result, 'output_dir') && ~isempty(result.output_dir)
    theta = copley.analysis.writeCommissioningArtifacts( ...
        result, result.output_dir, 'ShowFigures', true);
else
    theta = copley.analysis.buildThetaResult(result);
end

if ~logical(theta.accepted)
    error('magnetic_pole_commissioning_live:EstimationRejected', ...
        'Magnetic pole estimation was rejected: %s', theta.quality.reason);
end

fprintf('reference_position_count: %d\n', int32(theta.reference_position_count));
fprintf('reference_commutation_angle: %u count / %.12g deg\n', ...
    uint16(theta.reference_commutation_angle), ...
    double(theta.reference_commutation_angle_deg));
fprintf('Estimated theta_offset_deg: %.12g\n', ...
    double(theta.theta_at_estimation_deg));
fprintf('D-axis angle at absolute encoder 0: %.12g deg\n', ...
    double(theta.theta_at_absolute_encoder_zero_deg));
