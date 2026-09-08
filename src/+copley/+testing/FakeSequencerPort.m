classdef FakeSequencerPort < copley.ports.SequencerPort
    properties
        CommandLog = {}
        Heartbeats = []
        StartedProtocols = zeros(0, 1, 'uint16')
        CurrentProtocol = uint16(0)
        PollsInProtocol = 0
        PollsPerProtocol = 2
        RejectCommandId = ''
        FaultProtocol = uint16(0)
        FaultAfterPolls = 1
        FaultReason = 'heartbeat_expired'
        AbortCount = 0
        Running = false
    end

    methods
        function ack = sendCommand(obj, command)
            obj.CommandLog{end+1} = command;
            ack = struct('accepted', true, 'request_id', command.request_id, 'reason', '');
            if ~isempty(obj.RejectCommandId) && strcmp(command.command_id, obj.RejectCommandId)
                ack.accepted = false;
                ack.reason = 'forced command rejection';
                return;
            end

            if strcmp(command.command_id, 'prepare_protocol')
                obj.CurrentProtocol = uint16(command.protocol_id);
                obj.PollsInProtocol = 0;
            elseif strcmp(command.command_id, 'start_protocol')
                obj.Running = true;
                obj.CurrentProtocol = uint16(command.protocol_id);
                obj.StartedProtocols(end+1, 1) = uint16(command.protocol_id);
                obj.PollsInProtocol = 0;
            elseif strcmp(command.command_id, 'abort_protocol')
                obj.AbortCount = obj.AbortCount + 1;
                obj.Running = false;
            end
        end

        function writeHeartbeat(obj, leaseId, timestamp_s)
            obj.Heartbeats(end+1, :) = [double(leaseId), double(timestamp_s)];
        end

        function status = readStatus(obj)
            status = struct('busy', obj.Running, 'done', false, ...
                'fault', false, 'reason', '');
            if ~obj.Running
                return;
            end
            obj.PollsInProtocol = obj.PollsInProtocol + 1;
            if obj.FaultProtocol == obj.CurrentProtocol ...
                    && obj.PollsInProtocol >= obj.FaultAfterPolls
                status.busy = false;
                status.fault = true;
                status.reason = obj.FaultReason;
                obj.Running = false;
                return;
            end
            if obj.PollsInProtocol >= obj.PollsPerProtocol
                status.busy = false;
                status.done = true;
                obj.Running = false;
            end
        end
    end
end
