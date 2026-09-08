classdef (Abstract) RunStore < handle
    %RUNSTORE Persistence boundary for commissioning results.
    methods (Abstract)
        runDir = saveResult(obj, result)
    end
end
