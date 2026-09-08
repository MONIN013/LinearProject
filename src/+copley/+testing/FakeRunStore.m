classdef FakeRunStore < copley.ports.RunStore
    properties
        Results = {}
    end

    methods
        function runDir = saveResult(obj, result)
            obj.Results{end+1} = result;
            runDir = '';
        end
    end
end
