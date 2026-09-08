classdef RecordingAdsClient < handle
    %RECORDINGADSCLIENT Capture ADS writes without connecting to a PLC.
    properties
        DryRun = false
        Writes = struct('symbol', {}, 'value', {})
        Symbols
    end

    methods
        function obj = RecordingAdsClient(dryRun)
            obj.Symbols = containers.Map('KeyType', 'char', ...
                'ValueType', 'any');
            if nargin >= 1
                obj.DryRun = logical(dryRun);
            end
            obj.Symbols('GVL_MotorRuntime.Command.ControlWord') = uint16(0);
            obj.Symbols('GVL_MotorRuntime.Command.TargetTorque') = int16(0);
            obj.Symbols(['GVL_MotorRuntimeInternal.CommissioningCommand.' ...
                'ControlWord']) = uint16(0);
            obj.Symbols(['GVL_MotorRuntimeInternal.CommissioningCommand.' ...
                'TargetTorque']) = int16(0);
            obj.Symbols( ...
                'GVL_MotorRuntimeInternal.CommutationOverride.enable') = false;
        end

        function writeSymbol(obj, symbol, value)
            symbol = char(symbol);
            entry = struct('symbol', symbol, 'value', value);
            obj.Writes(end+1) = entry;
            obj.Symbols(symbol) = value;
        end

        function writeMotorReference(obj, symbol, value)
            obj.writeSymbol(symbol, value);
            symbol = char(symbol);
            fields = {'reference_position_count', ...
                'reference_commutation_angle', 'electrical_direction'};
            for i = 1:numel(fields)
                fieldName = fields{i};
                obj.Symbols([symbol '.' fieldName]) = value.(fieldName);
            end
        end

        function writeMotorReferenceValid(obj, symbol, value)
            obj.writeSymbol(symbol, logical(value));
        end

        function writeMotorCalibration(obj, symbol, value)
            obj.writeMotorReference(symbol, value);
        end

        function value = readSymbol(obj, symbol)
            symbol = char(symbol);
            if isKey(obj.Symbols, symbol)
                value = obj.Symbols(symbol);
            else
                value = [];
            end
        end
    end
end
