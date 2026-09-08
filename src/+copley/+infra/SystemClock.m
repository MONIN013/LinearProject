classdef SystemClock < copley.ports.Clock
    methods
        function t = nowSeconds(obj) %#ok<MANU>
            t = now() * 86400.0;
        end

        function pause(obj, duration_s) %#ok<INUSD>
            pause(duration_s);
        end
    end
end
