classdef FakeClock < copley.ports.Clock
    properties
        Time_s = 0.0
        Pauses_s = []
    end

    methods
        function value = nowSeconds(obj)
            value = obj.Time_s;
        end

        function pause(obj, seconds)
            seconds = double(seconds);
            obj.Pauses_s(end+1, 1) = seconds;
            obj.Time_s = obj.Time_s + seconds;
        end
    end
end
