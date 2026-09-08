classdef CommissioningUseCase < handle
    %COMMISSIONINGUSECASE Protocol 1 -> 2 -> 3 -> optional registration.
    properties
        MotorPort
        SequencerPort
        LoggerPort
        RunStore
        Clock
        ProtocolSpecs
        ApplyCalibration
        ApplyInterimCalibration
    end

    methods
        function obj = CommissioningUseCase(motorPort, sequencerPort, loggerPort, runStore, clock, specs, applyCalibration, applyInterimCalibration)
            if nargin < 6 || isempty(specs)
                specs = copley.protocols.defaultProtocolSpecs();
            end
            if nargin < 7 || isempty(applyCalibration)
                applyCalibration = true;
            end
            if nargin < 8 || isempty(applyInterimCalibration)
                applyInterimCalibration = true;
            end
            obj.MotorPort = motorPort;
            obj.SequencerPort = sequencerPort;
            obj.LoggerPort = loggerPort;
            obj.RunStore = runStore;
            obj.Clock = clock;
            obj.ProtocolSpecs = specs;
            obj.ApplyCalibration = logical(applyCalibration);
            obj.ApplyInterimCalibration = logical(applyInterimCalibration);
        end

        function out = run(obj, plan)
            runProtocol = copley.app.RunProtocolUseCase( ...
                obj.SequencerPort, obj.LoggerPort, obj.Clock);
            analyzer = copley.app.AnalyzeProtocolUseCase();
            specs = localSelectProtocolSpecs(obj.ProtocolSpecs, plan);

            protocolRuns = {};
            results = {};
            protocolPlans = {};
            accepted = true;
            rejectionReason = '';
            workingPlan = plan;
            for i = 1:numel(specs)
                spec = specs(i);
                protocolPlans{end+1} = workingPlan; %#ok<AGROW>
                protocolRuns{end+1} = runProtocol.run(workingPlan, spec); %#ok<AGROW>
                results{end+1} = analyzer.run(protocolRuns{end}.rawLog, spec, workingPlan); %#ok<AGROW>
                quality = results{end}.quality;
                if ~isfield(quality, 'accepted') || ~logical(quality.accepted)
                    accepted = false;
                    rejectionReason = quality.reason;
                    break;
                end
                if i < numel(specs)
                    workingPlan = localUpdateWorkingPlan(workingPlan, results{end});
                    if obj.ApplyInterimCalibration
                        obj.MotorPort.stageReference( ...
                            localWorkingCalibration(workingPlan));
                    end
                end
            end

            out = struct();
            out.schema_version = 'new-architecture-1.0.0';
            out.protocol_plans = protocolPlans;
            out.protocol_runs = protocolRuns;
            out.protocol_results = results;
            out.accepted = logical(accepted);
            out.rejection_reason = rejectionReason;
            out.calibration_applied = false;

            if accepted
                calibration = copley.domain.makeCalibrationRecord( ...
                    plan, results, obj.Clock.nowSeconds());
                out.calibration = calibration;
                if obj.ApplyCalibration
                    obj.MotorPort.registerReference(calibration);
                    out.calibration_applied = true;
                else
                    out.calibration_write_skipped_reason = ...
                        'ApplyCalibration=false';
                end
            end

            out.output_dir = obj.RunStore.saveResult(out);
        end
    end
end

function specs = localSelectProtocolSpecs(allSpecs, plan)
specs = allSpecs;
if ~isstruct(plan) || ~isfield(plan, 'protocol_order') ...
        || isempty(plan.protocol_order)
    return;
end

order = uint16(plan.protocol_order(:)');
selected = allSpecs([]);
for i = 1:numel(order)
    match = [];
    for j = 1:numel(allSpecs)
        if uint16(allSpecs(j).ProtocolId) == order(i)
            match = allSpecs(j);
            break;
        end
    end
    if isempty(match)
        error('copley:CommissioningUseCase:UnknownProtocolId', ...
            'protocol_order contains unknown protocol_id=%u.', uint16(order(i)));
    end
    selected(end+1) = match; %#ok<AGROW>
end
specs = selected;
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

function calibration = localWorkingCalibration(plan)
seed = struct( ...
    'theta_offset_hat_rad', double(localField(plan, ...
    'initial_theta_offset_guess_rad', 0.0)), ...
    'recommended_q_axis_sign', int16(localField(plan, 'q_axis_sign', 1)));
calibration = copley.domain.makeCalibrationRecord(plan, {seed}, 0.0);
calibration.metadata.accepted = false;
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
