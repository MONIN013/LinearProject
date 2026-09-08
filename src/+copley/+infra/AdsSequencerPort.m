classdef AdsSequencerPort < copley.ports.SequencerPort
    %ADSSEQUENCERPORT Command mailbox and heartbeat ADS adapter.
    properties
        Client
        CommandSymbol = 'GVL_ExperimentSequencer.command'
        ParamsSymbol = 'GVL_ExperimentSequencer.protocolParams'
        HeartbeatSymbol = 'GVL_ExperimentSequencer.heartbeat'
        StatusSymbol = 'GVL_ExperimentSequencer.status'
        TaskPeriodSymbol = 'GVL_ExperimentSequencer.taskPeriod_s'
        PollTimeout_s = 5.0
        PollPeriod_s = 0.002
        HeartbeatCounter = uint32(0)
        DryRunStarted = false
        DryRunReadCount = 0
    end

    methods
        function obj = AdsSequencerPort(client, varargin)
            obj.Client = client;
            if nargin > 1
                opts = varargin{1};
                obj.PollTimeout_s = localGet(opts, 'timeout_s', obj.PollTimeout_s);
            end
        end

        function ack = sendCommand(obj, command)
            mailbox = obj.toMailbox(command);
            if mailbox.command_id == uint16(1) && isfield(command, 'params') ...
                    && isstruct(command.params) && ~isempty(fieldnames(command.params))
                obj.Client.writeSymbol(obj.ParamsSymbol, command.params);
            end
            if mailbox.command_id == uint16(2)
                obj.writeHeartbeat(command.lease_id, 0.0);
            end
            obj.Client.writeSymbol(obj.CommandSymbol, mailbox);

            if obj.Client.DryRun
                ack = struct('accepted', true, 'request_id', command.request_id, 'reason', '');
                if mailbox.command_id == uint16(2)
                    obj.DryRunStarted = true;
                    obj.DryRunReadCount = 0;
                elseif mailbox.command_id == uint16(3) || mailbox.command_id == uint16(4)
                    obj.DryRunStarted = false;
                end
                return;
            end

            if mailbox.command_id == uint16(2)
                obj.writeHeartbeat(command.lease_id, 0.0);
            end
            deadline = tic;
            while toc(deadline) < obj.PollTimeout_s
                if mailbox.command_id == uint16(2)
                    obj.writeHeartbeat(command.lease_id, 0.0);
                end
                echoed = obj.Client.readSymbol(obj.CommandSymbol);
                if isstruct(echoed) && isfield(echoed, 'last_accepted_request_id') ...
                        && uint32(echoed.last_accepted_request_id) == uint32(command.request_id)
                    ack = struct('accepted', true, 'request_id', command.request_id, 'reason', '');
                    return;
                end
                if isstruct(echoed) && isfield(echoed, 'last_rejected_request_id') ...
                        && uint32(echoed.last_rejected_request_id) == uint32(command.request_id)
                    reason = localGet(echoed, 'rejection_reason', 'rejected');
                    ack = struct('accepted', false, 'request_id', command.request_id, 'reason', reason);
                    return;
                end
                pause(obj.PollPeriod_s);
            end
            error('copley:AdsSequencerPort:AckTimeout', ...
                'Timed out waiting for command request_id=%u.', uint32(command.request_id));
        end

        function writeHeartbeat(obj, leaseId, timestamp_s) %#ok<INUSD>
            obj.HeartbeatCounter = obj.HeartbeatCounter + uint32(1);
            heartbeat = struct('lease_id', uint32(leaseId), 'counter', obj.HeartbeatCounter);
            obj.Client.writeSymbol(obj.HeartbeatSymbol, heartbeat);
        end

        function status = readStatus(obj)
            if obj.Client.DryRun
                obj.DryRunReadCount = obj.DryRunReadCount + 1;
                status = struct('done', false, 'fault', false, ...
                    'fault_id', uint32(0));
                if obj.DryRunStarted && obj.DryRunReadCount > 1
                    status.done = true;
                    obj.DryRunStarted = false;
                end
                return;
            end
            status = obj.Client.readSymbol(obj.StatusSymbol);
        end

        function taskPeriod_s = readTaskPeriod_s(obj)
            taskPeriod_s = double(obj.Client.readSymbol(obj.TaskPeriodSymbol));
            if ~isscalar(taskPeriod_s) || ~isfinite(taskPeriod_s) || taskPeriod_s <= 0
                error('copley:AdsSequencerPort:InvalidTaskPeriod', ...
                    'PLC task period must be a positive finite scalar.');
            end
        end

        function mailbox = toMailbox(obj, command) %#ok<INUSD>
            mailbox = struct();
            mailbox.command_id = copley.infra.commandIdToPlc(command.command_id);
            mailbox.request_id = uint32(command.request_id);
            mailbox.lease_id = uint32(command.lease_id);
            mailbox.protocol_id = uint16(command.protocol_id);
            mailbox.last_accepted_request_id = uint32(0);
            mailbox.last_rejected_request_id = uint32(0);
            mailbox.rejection_reason = '';
        end
    end
end

function value = localGet(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
