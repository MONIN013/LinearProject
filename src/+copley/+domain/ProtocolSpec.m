classdef ProtocolSpec
    %PROTOCOLSPEC Analysis and acceptance behavior for one protocol.
    properties
        ProtocolId
        Name
        Analyzer
        Acceptance
    end

    methods
        function obj = ProtocolSpec(protocolId, name, analyzer, acceptance)
            if nargin > 0
                obj.ProtocolId = uint16(protocolId);
                obj.Name = char(name);
                obj.Analyzer = analyzer;
                obj.Acceptance = acceptance;
            end
        end

        function result = analyze(obj, rawLog, plan)
            result = obj.Analyzer(rawLog, plan);
            quality = obj.Acceptance(result);
            result.quality = quality;
        end
    end
end
