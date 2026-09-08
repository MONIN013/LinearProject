function theta = analyze_commissioning_folder(runDir, varargin)
%ANALYZE_COMMISSIONING_FOLDER Re-analyze a saved commissioning run folder.
copley_project_root();

p = inputParser;
addParameter(p, 'WriteArtifacts', true);
addParameter(p, 'Plan', []);
parse(p, varargin{:});
opts = p.Results;

if nargin < 1 || isempty(runDir)
    error('analyze_commissioning_folder:MissingRunDir', 'runDir is required.');
end
savedResultPath = fullfile(runDir, 'commissioning_result.mat');
if exist(savedResultPath, 'file')
    loaded = load(savedResultPath, 'result');
    if ~isfield(loaded, 'result') || ~isstruct(loaded.result) ...
            || ~isfield(loaded.result, 'protocol_runs')
        error('analyze_commissioning_folder:UnsupportedResult', ...
            'Expected commissioning_result.mat containing result.protocol_runs.');
    end
    result = localAnalyzeSavedResult(loaded.result, opts.Plan);
else
    matPath = fullfile(runDir, 'log_raw.mat');
    if ~exist(matPath, 'file')
        error('analyze_commissioning_folder:MissingLog', ...
            'Expected %s or %s.', savedResultPath, matPath);
    end
    loaded = load(matPath);
    if ~isfield(loaded, 'run') || ~isstruct(loaded.run) ...
            || ~isfield(loaded.run, 'rawTable')
        error('analyze_commissioning_folder:UnsupportedLog', ...
            'Expected log_raw.mat containing run.rawTable.');
    end
    result = localAnalyzeLegacyRun(loaded.run, opts.Plan);
end

theta = copley.analysis.buildThetaResult(result);
if logical(opts.WriteArtifacts)
    theta = copley.analysis.writeCommissioningArtifacts(result, runDir);
end
end

function result = localAnalyzeSavedResult(savedResult, suppliedPlan)
plans = savedResult.protocol_plans;
if nargin < 2 || isempty(suppliedPlan)
    suppliedPlan = copley.domain.defaultExperimentPlan();
end
specs = copley.protocols.defaultProtocolSpecs();
protocolRuns = savedResult.protocol_runs;
protocolPlans = cell(1, numel(protocolRuns));
protocolResults = cell(1, numel(protocolRuns));
accepted = true;
rejectionReason = '';
workingPlan = suppliedPlan;
analyzer = copley.app.AnalyzeProtocolUseCase();
for i = 1:numel(protocolRuns)
    if numel(plans) >= i && isstruct(plans{i})
        workingPlan = plans{i};
    end
    rawLog = protocolRuns{i}.rawLog;
    spec = localFindSpec(specs, rawLog.protocol_id);
    protocolPlans{i} = workingPlan;
    protocolResults{i} = analyzer.run(rawLog, spec, workingPlan);
    quality = protocolResults{i}.quality;
    if ~isfield(quality, 'accepted') || ~logical(quality.accepted)
        accepted = false;
        rejectionReason = quality.reason;
        protocolRuns = protocolRuns(1:i);
        protocolPlans = protocolPlans(1:i);
        protocolResults = protocolResults(1:i);
        break;
    end
    workingPlan = localUpdateWorkingPlan(workingPlan, protocolResults{i});
end
result = localResult(protocolPlans, protocolRuns, protocolResults, accepted, rejectionReason);
end

function result = localAnalyzeLegacyRun(run, suppliedPlan)
plan = suppliedPlan;
if isempty(plan)
    plan = localPlanFromRun(run);
end

T = run.rawTable;
specs = copley.protocols.defaultProtocolSpecs();
analyzer = copley.app.AnalyzeProtocolUseCase();
protocolRuns = {};
protocolResults = {};
protocolPlans = {};
workingPlan = plan;
accepted = true;
rejectionReason = '';

for i = 1:numel(specs)
    spec = specs(i);
    workingPlan = localApplyProtocolManifest(workingPlan, run, spec.ProtocolId);
    rawLog = struct('protocol_id', uint16(spec.ProtocolId), ...
        'rawTable', T(T.protocol_id == uint16(spec.ProtocolId), :));
    protocolPlans{end+1} = workingPlan; %#ok<AGROW>
    protocolRuns{end+1} = struct('protocol_id', uint16(spec.ProtocolId), ...
        'rawLog', rawLog); %#ok<AGROW>
    protocolResults{end+1} = analyzer.run(rawLog, spec, workingPlan); %#ok<AGROW>
    q = protocolResults{end}.quality;
    if ~isfield(q, 'accepted') || ~logical(q.accepted)
        accepted = false;
        rejectionReason = q.reason;
        break;
    end
    workingPlan = localUpdateWorkingPlan(workingPlan, protocolResults{end});
end

result = localResult(protocolPlans, protocolRuns, protocolResults, accepted, rejectionReason);
end

function spec = localFindSpec(specs, protocolId)
for i = 1:numel(specs)
    if uint16(specs(i).ProtocolId) == uint16(protocolId)
        spec = specs(i);
        return;
    end
end
error('analyze_commissioning_folder:UnknownProtocol', ...
    'Unsupported protocol_id=%u in saved result.', uint16(protocolId));
end

function result = localResult(protocolPlans, protocolRuns, protocolResults, accepted, rejectionReason)
result = struct();
result.schema_version = 'new-architecture-1.0.0';
result.protocol_plans = protocolPlans;
result.protocol_runs = protocolRuns;
result.protocol_results = protocolResults;
result.accepted = logical(accepted);
result.rejection_reason = rejectionReason;
result.calibration_applied = false;
end

function plan = localPlanFromRun(run)
plan = copley.domain.defaultExperimentPlan();

if isfield(run, 'manifest') && isstruct(run.manifest)
    manifest = run.manifest;
    if isfield(manifest, 'protocols') && numel(manifest.protocols) > 0
        p = manifest.protocols(1).params;
        plan = localMergeKnown(plan, p);
        plan = localAddProtocol1Reference(plan, manifest);
    end
    if isfield(manifest, 'scaling')
        s = manifest.scaling;
        plan.position_raw_zero = int32(localField(s, 'panasonic_position_raw_zero', plan.position_raw_zero));
        plan.position_zero_m = localField(s, 'panasonic_position_zero_m', plan.position_zero_m);
        plan.position_m_per_count = localField(s, 'panasonic_position_m_per_count', plan.position_m_per_count);
        plan.velocity_mps_per_count = localField(s, 'panasonic_velocity_mps_per_count', plan.velocity_mps_per_count);
        plan.target_torque_A_per_1000 = localField(s, 'copley_target_torque_A_per_1000', plan.target_torque_A_per_1000);
        plan.actual_current_A_per_1000 = localField(s, 'copley_actual_current_A_per_1000', plan.actual_current_A_per_1000);
    end
end
end

function plan = localApplyProtocolManifest(plan, run, protocolId)
if ~isfield(run, 'manifest') || ~isstruct(run.manifest) ...
        || ~isfield(run.manifest, 'protocols')
    return;
end
protocols = run.manifest.protocols;
for i = 1:numel(protocols)
    if isfield(protocols(i), 'protocol_id') ...
            && uint16(protocols(i).protocol_id) == uint16(protocolId) ...
            && isfield(protocols(i), 'params')
        plan = localMergeKnown(plan, protocols(i).params);
        return;
    end
end
end

function plan = localAddProtocol1Reference(plan, manifest)
if ~isfield(manifest, 'protocols') || numel(manifest.protocols) < 2
    return;
end
p2 = manifest.protocols(2).params;
if ~isstruct(p2) || ~isfield(p2, 'initial_theta_offset_guess_rad')
    return;
end
axisShift = localField(plan, 'protocol2_axis_shift_rad', pi/4);
if ~isfield(plan, 'analysis') || ~isstruct(plan.analysis)
    plan.analysis = struct();
end
plan.analysis.protocol1_theta_reference_rad = ...
    copley.analysis.wrapTo2Pi(double(p2.initial_theta_offset_guess_rad) - axisShift);
end

function plan = localMergeKnown(plan, p)
if ~isstruct(p)
    return;
end
plan.tau_e_m = localField(p, 'tau_e_m', plan.tau_e_m);
plan.x_ref_m = localField(p, 'x_ref_m', plan.x_ref_m);
plan.q_axis_sign = int16(localField(p, 'q_axis_sign', plan.q_axis_sign));
plan.electrical_angle_sign = int16(localField(p, ...
    'electrical_angle_sign', plan.electrical_angle_sign));
plan.initial_theta_offset_guess_rad = localField(p, ...
    'initial_theta_offset_guess_rad', plan.initial_theta_offset_guess_rad);
plan.position_raw_zero = int32(localField(p, 'position_raw_zero', plan.position_raw_zero));
plan.position_zero_m = localField(p, 'position_zero_m', plan.position_zero_m);
plan.position_m_per_count = localField(p, 'position_m_per_count', plan.position_m_per_count);
plan.velocity_mps_per_count = localField(p, 'velocity_mps_per_count', plan.velocity_mps_per_count);
plan.max_target_count = int16(localField(p, 'max_target_count', plan.max_target_count));
plan.max_actual_count = int16(localField(p, 'max_actual_count', plan.max_actual_count));
plan.current_ramp_count_per_s = localField(p, ...
    'current_ramp_count_per_s', plan.current_ramp_count_per_s);
plan.protocol2_repeat_count = uint16(localField(p, 'protocol2_repeat_count', plan.protocol2_repeat_count));
plan.protocol2_vmax_mps = localField(p, 'protocol2_vmax_mps', plan.protocol2_vmax_mps);
plan.protocol2_accel_time_s = localField(p, 'protocol2_accel_time_s', plan.protocol2_accel_time_s);
plan.protocol2_const_time_s = localField(p, 'protocol2_const_time_s', plan.protocol2_const_time_s);
plan.protocol2_pause_time_s = localField(p, 'protocol2_pause_time_s', plan.protocol2_pause_time_s);
plan.protocol2_axis_shift_rad = localField(p, 'protocol2_axis_shift_rad', pi/4);
if ~isfield(plan, 'analysis') || ~isstruct(plan.analysis)
    plan.analysis = struct();
end
plan.analysis.protocol2_max_axis_shift_error_deg = 7.0;
plan.analysis.protocol2_max_ramp_limited_fraction = 0.10;
plan.analysis.protocol2_max_near_zero_denominator_fraction = 0.10;
plan.analysis.protocol2_max_low_current_pair_fraction = 0.50;
plan.analysis.protocol2_edge_discard_s = 0.002;
end

function plan = localUpdateWorkingPlan(plan, result)
if isstruct(result) && isfield(result, 'next_theta_offset_seed_rad')
    plan.initial_theta_offset_guess_rad = double(result.next_theta_offset_seed_rad);
elseif isstruct(result) && isfield(result, 'theta_offset_hat_rad')
    plan.initial_theta_offset_guess_rad = double(result.theta_offset_hat_rad);
end
if isstruct(result) && isfield(result, 'recommended_q_axis_sign')
    plan.q_axis_sign = int16(result.recommended_q_axis_sign);
end
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
