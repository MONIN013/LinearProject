classdef AdsMotorRuntimePort < copley.ports.MotorRuntimePort
    properties
        Client
        StatusSymbol = 'GVL_MotorRuntime.Status'
        FeedbackSymbol = 'GVL_MotorRuntimeInternal.Feedback'
    end

    methods
        function obj = AdsMotorRuntimePort(client)
            obj.Client = client;
        end

        function status = readStatus(obj)
            status = obj.Client.readSymbol(obj.FeedbackSymbol);
            if isempty(status) || ~isstruct(status)
                status = obj.Client.readSymbol(obj.StatusSymbol);
            end
            status = localNormalizeDriverStatus(status);
        end

        function reference = stageReference(obj, reference)
            [payload, reference] = ...
                copley.domain.toMotorRuntimeCalibrationPayload(reference);
            symbol = obj.referenceSymbol( ...
                reference, 'CommissioningReference');
            obj.writeAndVerifyReference(symbol, payload);
        end

        function reference = registerReference(obj, reference)
            [payload, reference] = ...
                copley.domain.toMotorRuntimeCalibrationPayload(reference);
            if ~logical(obj.Client.DryRun)
                obj.assertProductionRegistrationIdle();
            end
            symbol = obj.referenceSymbol(reference, 'RegisteredReference');
            validSymbol = sprintf( ...
                'GVL_MotorRuntimeInternal.RegisteredReferenceValid[%u]', ...
                uint16(reference.axis_index));
            obj.writeAndVerifyReferenceValid(validSymbol, false);
            obj.writeAndVerifyReference(symbol, payload);
            obj.writeAndVerifyReferenceValid(validSymbol, true);
        end

        function references = registerReferenceSet(obj, references)
            if ~iscell(references) || isempty(references)
                error('copley:AdsMotorRuntimePort:InvalidReferenceSet', ...
                    'references must be one non-empty cell array.');
            end

            payloads = cell(size(references));
            symbols = cell(size(references));
            validSymbols = cell(size(references));
            for i = 1:numel(references)
                [payloads{i}, references{i}] = ...
                    copley.domain.toMotorRuntimeCalibrationPayload(references{i});
                symbols{i} = obj.referenceSymbol( ...
                    references{i}, 'RegisteredReference');
                validSymbols{i} = sprintf( ...
                    'GVL_MotorRuntimeInternal.RegisteredReferenceValid[%u]', ...
                    uint16(references{i}.axis_index));
            end

            if ~logical(obj.Client.DryRun)
                obj.assertProductionRegistrationIdle();
            end
            for i = 1:numel(validSymbols)
                obj.writeAndVerifyReferenceValid(validSymbols{i}, false);
            end
            for i = 1:numel(symbols)
                obj.writeAndVerifyReference(symbols{i}, payloads{i});
            end

            % Keep all selected axes unusable until every record passes exact
            % readback and the external command remains idle.
            if ~logical(obj.Client.DryRun)
                obj.assertProductionRegistrationIdle();
            end
            for i = 1:numel(validSymbols)
                obj.writeAndVerifyReferenceValid(validSymbols{i}, true);
            end
        end

        function symbol = referenceSymbol(obj, reference, collectionName) %#ok<INUSL>
            axisIndex = uint16(1);
            if isstruct(reference) && isfield(reference, 'axis_index')
                axisIndex = uint16(reference.axis_index);
            end
            if axisIndex < 1 || axisIndex > 4
                error('copley:AdsMotorRuntimePort:InvalidAxisIndex', ...
                    'axis_index must be from 1 through 4.');
            end
            allowed = {'CommissioningReference', 'RegisteredReference'};
            if ~any(strcmp(collectionName, allowed))
                error('copley:AdsMotorRuntimePort:InvalidReferenceCollection', ...
                    'Unknown MotorRuntime reference collection %s.', ...
                    char(collectionName));
            end
            symbol = sprintf( ...
                'GVL_MotorRuntimeInternal.%s[%u]', ...
                char(collectionName), axisIndex);
        end

        function writeAndVerifyReference(obj, symbol, payload)
            % One whole-record write prevents mixed position/angle/direction
            % observations in the PLC task.
            obj.Client.writeMotorReference(symbol, payload);
            if logical(obj.Client.DryRun)
                actual = obj.Client.readSymbol(symbol);
            else
                actual = struct();
                actual.reference_position_count = localDecodeScalar( ...
                    obj.Client.readSymbol( ...
                    [symbol '.reference_position_count']), 'int32');
                actual.reference_commutation_angle = localDecodeScalar( ...
                    obj.Client.readSymbol( ...
                    [symbol '.reference_commutation_angle']), 'uint16');
                actual.electrical_direction = localDecodeScalar( ...
                    obj.Client.readSymbol( ...
                    [symbol '.electrical_direction']), 'int16');
            end
            localAssertReferenceReadback(symbol, payload, actual);
        end

        function writeAndVerifyReferenceValid(obj, symbol, expected)
            obj.Client.writeMotorReferenceValid(symbol, logical(expected));
            actual = localDecodeScalar(obj.Client.readSymbol(symbol), 'logical');
            if isempty(actual) || ~isscalar(actual) ...
                    || logical(actual) ~= logical(expected)
                error('copley:AdsMotorRuntimePort:ReferenceValidReadbackMismatch', ...
                    'Reference-valid readback mismatch at %s.', symbol);
            end
        end

        function assertProductionRegistrationIdle(obj)
            normalControlWordSymbol = ...
                'GVL_MotorRuntime.Command.ControlWord';
            normalControlWord = localDecodeScalar( ...
                obj.Client.readSymbol(normalControlWordSymbol), 'uint16');
            if isempty(normalControlWord)
                error('copley:AdsMotorRuntimePort:IdlePreflightUnavailable', ...
                    'Could not read %s before production registration.', ...
                    normalControlWordSymbol);
            end
            operationEnabledMask = uint16(hex2dec('000F'));
            if ~isnumeric(normalControlWord) || ~isscalar(normalControlWord) ...
                    || bitand(uint16(normalControlWord), ...
                    operationEnabledMask) == operationEnabledMask
                error('copley:AdsMotorRuntimePort:RegistrationNotIdle', ...
                    ['Refusing production reference registration while ' ...
                     '%s requests Operation Enabled.'], ...
                    normalControlWordSymbol);
            end

            checks = { ...
                'GVL_MotorRuntime.Command.TargetTorque', int16(0), 'int16'; ...
                ['GVL_MotorRuntimeInternal.CommissioningCommand.' ...
                 'ControlWord'], uint16(0), 'uint16'; ...
                ['GVL_MotorRuntimeInternal.CommissioningCommand.' ...
                 'TargetTorque'], int16(0), 'int16'; ...
                'GVL_MotorRuntimeInternal.CommutationOverride.enable', ...
                false, 'logical'};
            for i = 1:size(checks, 1)
                symbol = checks{i, 1};
                expected = checks{i, 2};
                actual = localDecodeScalar( ...
                    obj.Client.readSymbol(symbol), checks{i, 3});
                if isempty(actual)
                    error('copley:AdsMotorRuntimePort:IdlePreflightUnavailable', ...
                        'Could not read %s before production registration.', ...
                        symbol);
                end
                if ~isscalar(actual) || double(actual) ~= double(expected)
                    error('copley:AdsMotorRuntimePort:RegistrationNotIdle', ...
                        ['Refusing production reference registration while ' ...
                         '%s is not zero/disabled.'], symbol);
                end
            end
        end
    end
end

function value = localDecodeScalar(value, typeName)
if isempty(value)
    return;
end
if strcmp(typeName, 'logical')
    if isa(value, 'uint8')
        if isscalar(value)
            value = logical(value);
        end
    end
    return;
end
byteCounts = struct('int16', 2, 'uint16', 2, 'int32', 4);
if isa(value, 'uint8')
    if numel(value) == byteCounts.(typeName)
        value = typecast(uint8(value(:)'), typeName);
    end
end
end

function localAssertReferenceReadback(symbol, expected, actual)
fields = {'reference_position_count', ...
    'reference_commutation_angle', 'electrical_direction'};
for i = 1:numel(fields)
    name = fields{i};
    if ~isstruct(actual) || ~isfield(actual, name) ...
            || isempty(actual.(name)) || ~isscalar(actual.(name))
        error('copley:AdsMotorRuntimePort:ReferenceReadbackUnavailable', ...
            'Could not read back %s.%s.', symbol, name);
    end
    if double(actual.(name)) ~= double(expected.(name))
        error('copley:AdsMotorRuntimePort:ReferenceReadbackMismatch', ...
            ['Reference readback mismatch at %s.%s: expected %g, ' ...
             'received %g.'], symbol, name, double(expected.(name)), ...
            double(actual.(name)));
    end
end
end

function status = localNormalizeDriverStatus(status)
if ~isstruct(status)
    return;
end
if isfield(status, 'PositionActualValue') ...
        && ~isfield(status, 'encoder_position_raw')
    status.encoder_position_raw = int32(status.PositionActualValue);
end
if isfield(status, 'VelocityActualValue') ...
        && ~isfield(status, 'encoder_velocity_raw')
    status.encoder_velocity_raw = int32(status.VelocityActualValue);
end
if isfield(status, 'StatusWord') && ~isfield(status, 'copley_statusword')
    status.copley_statusword = uint16(status.StatusWord);
end
if isfield(status, 'TorqueActualValue') ...
        && ~isfield(status, 'copley_actual_current_count')
    status.copley_actual_current_count = int16(status.TorqueActualValue);
end
hasFaultId = isfield(status, 'fault_id');
if hasFaultId
    status.fault = uint32(status.fault_id) ~= 0;
elseif isfield(status, 'StatusWord')
    status.fault = bitand(uint16(status.StatusWord), ...
        uint16(hex2dec('0008'))) ~= 0;
    status.fault_id = uint32(0);
end
end
