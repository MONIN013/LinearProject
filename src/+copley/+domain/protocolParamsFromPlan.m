function params = protocolParamsFromPlan(plan, protocolId)
%PROTOCOLPARAMSFROMPLAN Build PLC DUT_ProtocolParams-compatible payload.
params = struct();
params.axis_index = uint16(localProtocolField(plan, protocolId, ...
    'axis_index', localField(plan, 'axis_index', 1)));

params.position_raw_zero = int32(localField(plan, 'position_raw_zero', 0));
params.position_zero_m = localField(plan, 'position_zero_m', 0.0);
params.position_m_per_count = localField(plan, 'position_m_per_count', 1.0e-7);
params.velocity_mps_per_count = localField(plan, 'velocity_mps_per_count', 1.0e-6);

params.x_soft_min_m = localField(plan, 'x_soft_min_m', -0.01);
params.x_soft_max_m = localField(plan, 'x_soft_max_m', 0.01);
params.max_velocity_mps = localProtocolField(plan, protocolId, ...
    'max_velocity_mps', localField(plan, 'max_velocity_mps', 0.02));

params.max_target_count = int16(localProtocolField(plan, protocolId, 'max_target_count', 50));
params.current_ramp_count_per_s = localProtocolField(plan, protocolId, ...
    'current_ramp_count_per_s', localField(plan, 'current_ramp_count_per_s', 500.0));

params.task_period_s = localField(plan, 'task_period_s', 0.000125);
params.settle_time_s = localProtocolField(plan, protocolId, 'settle_time_s', 0.05);
params.pulse_time_s = localProtocolField(plan, protocolId, 'pulse_time_s', 0.05);
params.post_time_s = localProtocolField(plan, protocolId, 'post_time_s', 0.05);
params.timeout_s = localProtocolField(plan, protocolId, 'timeout_s', 10.0);

params.angle_start_rad = localProtocolField(plan, protocolId, 'angle_start_rad', 0.0);
params.angle_step_rad = localProtocolField(plan, protocolId, 'angle_step_rad', 0.5235987755982988);
params.angle_count = uint16(localProtocolField(plan, protocolId, 'angle_count', 12));

params.protocol2_repeat_count = uint16(localField(plan, 'protocol2_repeat_count', 2));
params.protocol2_vmax_mps = localField(plan, 'protocol2_vmax_mps', 0.002);
params.protocol2_accel_time_s = localField(plan, 'protocol2_accel_time_s', 0.050);
params.protocol2_const_time_s = localField(plan, 'protocol2_const_time_s', 0.0);
params.protocol2_pause_time_s = localField(plan, 'protocol2_pause_time_s', 0.050);
params.speed_kp_count_per_mps = localField(plan, 'speed_kp_count_per_mps', 20000.0);
params.speed_ki_count_per_m = localField(plan, 'speed_ki_count_per_m', 0.0);
params.speed_integral_limit_count = int16(localField(plan, 'speed_integral_limit_count', 200));
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
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
end
