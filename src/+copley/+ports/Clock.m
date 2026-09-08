classdef (Abstract) Clock < handle
    %CLOCK Time boundary for deterministic use-case tests.
    methods (Abstract)
        value = nowSeconds(obj)
        pause(obj, seconds)
    end
end
