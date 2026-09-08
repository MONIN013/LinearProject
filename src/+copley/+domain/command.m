function cmd = command(commandId, requestId, plan, protocolSpec)
%COMMAND Build a CommandMailbox request struct.
if nargin < 4
    protocolSpec = [];
end
cmd = struct();
cmd.command_id = char(commandId);
cmd.request_id = uint32(requestId);
cmd.lease_id = uint32(plan.lease_id);
cmd.protocol_id = uint16(0);
cmd.payload = struct();
cmd.params = struct();
if ~isempty(protocolSpec)
    cmd.protocol_id = uint16(protocolSpec.ProtocolId);
    cmd.payload.protocol_name = protocolSpec.Name;
    cmd.params = copley.domain.protocolParamsFromPlan(plan, protocolSpec.ProtocolId);
end
end
