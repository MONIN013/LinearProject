classdef (Abstract) LoggerPort < handle
    %LOGGERPORT Boundary to the sequencer logger ring buffer.
    methods (Abstract)
        rawLog = downloadProtocol(obj, protocolId, varargin)
    end
end
