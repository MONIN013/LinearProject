classdef (Abstract) MotorRuntimePort < handle
    %MOTORRUNTIMEPORT Boundary to the MotorRuntime PLC project.
    methods (Abstract)
        status = readStatus(obj)
        reference = stageReference(obj, reference)
        reference = registerReference(obj, reference)
    end
end
