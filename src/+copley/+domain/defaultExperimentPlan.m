function plan = defaultExperimentPlan(leaseId)
%DEFAULTEXPERIMENTPLAN Build the new ExperimentPlan DTO.
if nargin < 1
    leaseId = uint32(1);
end

plan = struct();
plan.schema_version = 'new-architecture-1.0.0';
plan.lease_id = uint32(leaseId);
plan.heartbeat_period_s = 0.050;
plan.heartbeat_timeout_s = 0.150;
plan.task_period_s = 0.00025;
plan.protocol_order = uint16([1 2 3]);
plan.axis_index = uint16(1);
plan.tau_e_m = 0.036;
plan.x_ref_m = 0.0;
plan.q_axis_sign = int16(1);
plan.electrical_angle_sign = int16(1);
plan.position_raw_zero = int32(0);
plan.position_zero_m = 0.0;
plan.position_m_per_count = 1.0e-7;
plan.velocity_mps_per_count = 1.0e-6;
plan.initial_theta_offset_guess_rad = 0.0;
plan.calibration_version = uint16(2);
plan.x_soft_min_m = -0.01;
plan.x_soft_max_m = 0.01;
plan.max_velocity_mps = 0.02;
plan.i_rated_A = 1.0;
plan.target_torque_A_per_1000 = 0.1;
plan.actual_current_A_per_1000 = 0.1;
plan.max_target_count = int16(50);
plan.max_actual_count = int16(80);
plan.current_tracking_tol_count = int16(50);
plan.current_ramp_count_per_s = 500.0;
plan.protocol1 = struct('angle_start_rad', 0.0, ...
    'angle_step_rad', 0.5235987755982988, 'angle_count', uint16(12), ...
    'settle_time_s', 0.05, 'pulse_time_s', 0.05, 'post_time_s', 0.05, ...
    'timeout_s', 10.0, 'max_target_count', int16(50));
plan.protocol2 = struct('timeout_s', 30.0, 'max_target_count', int16(80));
plan.protocol3 = struct('angle_start_rad', 0.0, 'angle_step_rad', 0.0, ...
    'angle_count', uint16(1), 'settle_time_s', 0.05, 'pulse_time_s', 0.05, ...
    'post_time_s', 0.05, 'timeout_s', 5.0, 'max_target_count', int16(50));
plan.protocol2_repeat_count = uint16(2);
plan.protocol2_vmax_mps = 0.002;
plan.protocol2_accel_time_s = 0.050;
plan.protocol2_const_time_s = 0.0;
plan.protocol2_pause_time_s = 0.050;
plan.protocol2_axis_shift_rad = pi/4;
plan.speed_kp_count_per_mps = 20000.0;
plan.speed_ki_count_per_m = 0.0;
plan.speed_integral_limit_count = int16(200);
plan.analysis = struct();
plan.analysis.protocol1_min_required_dx_m = 5.0e-6;
plan.analysis.protocol1_min_r_squared = 0.80;
plan.analysis.protocol2_max_axis_shift_error_deg = 7.0;
plan.analysis.protocol2_max_ramp_limited_fraction = 0.10;
plan.analysis.protocol2_max_near_zero_denominator_fraction = 0.10;
plan.analysis.protocol2_max_low_current_pair_fraction = 0.50;
plan.analysis.protocol2_max_current_equality_mismatch_fraction = 0.20;
plan.analysis.protocol2_min_pair_current_count = 5;
plan.analysis.protocol2_ramp_delta_tol_count = 50;
plan.analysis.protocol2_edge_discard_s = 0.002;
plan.analysis.protocol3_min_response_m = 1.0e-8;
end
