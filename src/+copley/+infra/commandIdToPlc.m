function id = commandIdToPlc(commandId)
switch char(commandId)
    case 'prepare_protocol'
        id = uint16(1);
    case 'start_protocol'
        id = uint16(2);
    case 'abort_protocol'
        id = uint16(3);
    case 'reset'
        id = uint16(4);
    otherwise
        error('copley:commandIdToPlc:UnknownCommand', ...
            'Unknown command_id=%s.', char(commandId));
end
end
