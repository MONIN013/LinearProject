classdef RunProtocolUseCase < handle
    %RUNPROTOCOLUSECASE Execute one protocol through Sequencer and Logger ports.
    properties
        SequencerPort
        LoggerPort
        Clock
        SequencerIdle = false
    end

    methods
        function obj = RunProtocolUseCase(sequencerPort, loggerPort, clock)
            obj.SequencerPort = sequencerPort;
            obj.LoggerPort = loggerPort;
            obj.Clock = clock;
        end

        function out = run(obj, plan, protocolSpec)
            if ~obj.SequencerIdle
                resetCmd = copley.domain.command('reset', ...
                    uint32(protocolSpec.ProtocolId) * 100 + 0, plan, []);
                ack = obj.SequencerPort.sendCommand(resetCmd);
                copley.domain.assertCommandAccepted(ack, 'reset');
                obj.SequencerIdle = true;
            end

            prepareCmd = copley.domain.command('prepare_protocol', ...
                uint32(protocolSpec.ProtocolId) * 100 + 1, plan, protocolSpec);
            ack = obj.SequencerPort.sendCommand(prepareCmd);
            copley.domain.assertCommandAccepted(ack, 'prepare_protocol');
            obj.SequencerIdle = false;

            obj.primeHeartbeat(plan);
            startCmd = copley.domain.command('start_protocol', ...
                uint32(protocolSpec.ProtocolId) * 100 + 2, plan, protocolSpec);
            ack = obj.SequencerPort.sendCommand(startCmd);
            copley.domain.assertCommandAccepted(ack, 'start_protocol');

            completed = false;
            abortCleanup = onCleanup(@()obj.abortIfIncomplete(plan, completed));
            status = obj.pumpHeartbeatUntilDone(plan, protocolSpec);
            completed = true; %#ok<NASGU>
            delete(abortCleanup);

            rawLog = obj.LoggerPort.downloadProtocol(protocolSpec.ProtocolId, plan);
            resetCmd = copley.domain.command('reset', ...
                uint32(protocolSpec.ProtocolId) * 100 + 3, plan, []);
            ack = obj.SequencerPort.sendCommand(resetCmd);
            copley.domain.assertCommandAccepted(ack, 'reset');
            obj.SequencerIdle = true;

            out = struct();
            out.protocol_id = uint16(protocolSpec.ProtocolId);
            out.status = status;
            out.rawLog = rawLog;
        end

        function status = pumpHeartbeatUntilDone(obj, plan, protocolSpec)
            deadline_s = obj.Clock.nowSeconds() ...
                + obj.protocolTimeout_s(plan, protocolSpec) ...
                + localField(plan, 'matlab_timeout_margin_s', 2.0);
            while true
                obj.SequencerPort.writeHeartbeat(plan.lease_id, obj.Clock.nowSeconds());
                status = obj.SequencerPort.readStatus();
                if isfield(status, 'fault') && logical(status.fault)
                    error('copley:RunProtocolUseCase:SequencerFault', ...
                        'Sequencer fault: %s.', obj.statusReason(status));
                end
                if isfield(status, 'done') && logical(status.done)
                    return;
                end
                if obj.Clock.nowSeconds() > deadline_s
                    error('copley:RunProtocolUseCase:ProtocolTimeout', ...
                        'Timed out waiting for protocol_id=%u.', uint16(protocolSpec.ProtocolId));
                end
                obj.Clock.pause(obj.heartbeatPeriod_s(plan));
            end
        end

        function primeHeartbeat(obj, plan)
            count = max(1, min(10, round(localField(plan, ...
                'heartbeat_prime_count', 3))));
            period_s = min(localField(plan, ...
                'heartbeat_prime_period_s', 0.002), 0.005);
            for i = 1:count
                obj.SequencerPort.writeHeartbeat(plan.lease_id, obj.Clock.nowSeconds());
                obj.Clock.pause(period_s);
            end
        end

        function abortIfIncomplete(obj, plan, completed)
            if logical(completed)
                return;
            end
            abortCmd = copley.domain.command('abort_protocol', ...
                uint32(999000), plan, []);
            obj.SequencerPort.sendCommand(abortCmd);
        end

        function reason = statusReason(obj, status) %#ok<INUSD>
            reason = 'unknown';
            if isstruct(status) && isfield(status, 'reason')
                reason = char(status.reason);
            elseif isstruct(status) && isfield(status, 'fault_id')
                reason = sprintf('fault_id=%u', uint32(status.fault_id));
            end
        end

        function timeout_s = protocolTimeout_s(obj, plan, protocolSpec) %#ok<INUSD>
            timeout_s = localProtocolField(plan, protocolSpec.ProtocolId, 'timeout_s', 30.0);
        end

        function period_s = heartbeatPeriod_s(obj, plan) %#ok<INUSD>
            period_s = min(localField(plan, 'heartbeat_period_s', 0.050), 0.020);
        end
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
value = double(value);
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
value = double(value);
end
