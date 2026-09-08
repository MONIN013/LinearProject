function assertCommandAccepted(ack, commandId)
%ASSERTCOMMANDACCEPTED Fail fast on mailbox rejection.
if nargin < 2
    commandId = 'command';
end
if ~isstruct(ack) || ~isfield(ack, 'accepted') || ~logical(ack.accepted)
    reason = 'unknown rejection';
    if isstruct(ack) && isfield(ack, 'reason')
        reason = char(ack.reason);
    end
    error('copley:CommandRejected', '%s rejected: %s.', char(commandId), reason);
end
end
