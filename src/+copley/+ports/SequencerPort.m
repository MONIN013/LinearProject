classdef (Abstract) SequencerPort < handle
    %SEQUENCERPORT Command mailbox and heartbeat boundary.
    methods (Abstract)
        ack = sendCommand(obj, command)
        writeHeartbeat(obj, leaseId, timestamp_s)
        status = readStatus(obj)
    end
end
