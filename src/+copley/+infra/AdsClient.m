classdef AdsClient < handle
    %ADSCLIENT Minimal TE1410 ADS boundary with dry-run storage.
    properties (SetAccess = private)
        Config
        DryRun
        Ads
        PlcPort
        Symbols
    end

    methods
        function obj = AdsClient(config)
            if nargin < 1
                config = struct();
            end
            obj.Config = config;
            obj.DryRun = localGet(config, 'dryRun', true);
            obj.Symbols = containers.Map();
            if obj.DryRun
                obj.Ads = [];
                obj.PlcPort = [];
            else
                localSetupTe14xx();
                sharedAds = localGet(config, 'sharedAds', []);
                if isempty(sharedAds)
                    obj.Ads = TwinCAT.ADS.Port();
                else
                    obj.Ads = sharedAds;
                end
                obj.PlcPort = obj.openPortConnection(config);
            end
        end

        function value = readSymbol(obj, symbolName)
            symbolName = char(symbolName);
            if obj.DryRun
                if isKey(obj.Symbols, symbolName)
                    value = obj.Symbols(symbolName);
                else
                    value = [];
                end
                return;
            end
            if ~isempty(obj.PlcPort) && ismethod(obj.PlcPort, 'Read')
                value = obj.PlcPort.Read(symbolName, []);
            elseif ismethod(obj.Ads, 'ReadSymbol')
                value = obj.Ads.ReadSymbol(symbolName);
            elseif ismethod(obj.Ads, 'readSymbol')
                value = obj.Ads.readSymbol(symbolName);
            else
                error('copley:AdsClient:UnsupportedApi', ...
                    'Installed TE1410 ADS object does not expose a known symbol read method.');
            end
            value = localUnpackKnownSymbol(symbolName, value);
        end

        function value = readSymbolBytes(obj, symbolName, byteCount)
            symbolName = char(symbolName);
            byteCount = double(byteCount);
            if byteCount <= 0
                value = zeros(0, 1, 'uint8');
                return;
            end
            if obj.DryRun
                value = obj.readSymbol(symbolName);
                value = uint8(value(:));
                value = value(1:min(numel(value), byteCount));
                return;
            end

            template = zeros(1, byteCount, 'uint8');
            timeout_ms = max(1, round(double(localGet(obj.Config, ...
                'timeout_s', 5.0)) * 1000.0));
            if ~isempty(obj.PlcPort) && ismethod(obj.PlcPort, 'Read')
                value = obj.PlcPort.Read(symbolName, template, timeout_ms);
            elseif ismethod(obj.Ads, 'Read')
                value = obj.Ads.Read(symbolName, template, timeout_ms);
            else
                error('copley:AdsClient:UnsupportedApi', ...
                    'Installed TE1410 ADS object does not expose a raw byte read method.');
            end
            value = uint8(value(:));
        end

        function writeSymbol(obj, symbolName, value)
            symbolName = char(symbolName);
            obj.assertSafeWrite(symbolName);
            obj.writeSymbolValue(symbolName, value);
        end

        function assertSafeWrite(obj, symbolName)
            lowerName = lower(char(symbolName));
            forbidden = {'%q', 'gvl_io.', 'gvl_drive.', 'human_arm', ...
                'gvl_motorruntime.command', ...
                'gvl_motorruntime.commandguard', ...
                'gvl_motorruntime.normalauthorization', ...
                'gvl_motorruntime.commissioningcommand', ...
                'gvl_motorruntime.calibration', ...
                'gvl_motorruntimeinternal.commandguard', ...
                'gvl_motorruntimeinternal.normalauthorization', ...
                'gvl_motorruntimeinternal.commissioningcommand', ...
                'gvl_motorruntimeinternal.commutationoverride', ...
                'gvl_motorruntimeinternal.calibration', ...
                'gvl_motorruntimeinternal.registeredreference', ...
                'gvl_motorruntimeinternal.commissioningreference', ...
                'gvl_motorruntimeinternal.feedback', ...
                'gvl_motorruntimeinternal.runtimesafetystatus', ...
                'gvl_virtualcstinternal.', ...
                'gvl_experimentsequencer.drivecommand', ...
                'gvl_experimentsequencer.normaldrivecommand', ...
                'gvl_experimentsequencer.normalcommandguard', ...
                'gvl_experimentsequencer.normalauthorization', ...
                'gvl_experimentsequencer.virtualcstrequest', ...
                'gvl_experimentsequencer.virtualcstauthorization', ...
                'copleycontrolword', 'copleytargettorque', ...
                'copleycommutationangle', 'targettorque', ...
                'commutationangle', 'controlword'};
            for k = 1:numel(forbidden)
                if ~isempty(strfind(lowerName, forbidden{k}))
                    error('copley:AdsClient:ForbiddenWrite', ...
                        'Refusing unsafe ADS write to %s.', symbolName);
                end
            end
        end

        function plcPort = openPortConnection(obj, config)
            portIdentifier = localGet(config, 'portIdentifier', '');
            if isempty(portIdentifier)
                amsNetId = localGet(config, 'amsNetId', 'Local');
                adsPort = localGet(config, 'adsPort', 851);
                if isnumeric(adsPort)
                    adsPort = num2str(double(adsPort));
                end
                portIdentifier = [char(amsNetId) ':' char(adsPort)];
            end
            if ismethod(obj.Ads, 'GetPortConnection')
                plcPort = obj.Ads.GetPortConnection(portIdentifier);
            else
                plcPort = [];
            end
        end
    end

    methods (Access = ?copley.infra.AdsMotorRuntimePort)
        function writeMotorReference(obj, symbolName, value)
            symbolName = char(symbolName);
            lowerName = lower(symbolName);
            pattern = ['^gvl_motorruntimeinternal\.' ...
                '(registeredreference|commissioningreference)\[[1-4]\]$'];
            if isempty(regexp(lowerName, pattern, 'once'))
                error('copley:AdsClient:InvalidReferenceSymbol', ...
                    'Refusing motor reference write to %s.', symbolName);
            end
            obj.writeSymbolValue(symbolName, value);
        end

        function writeMotorReferenceValid(obj, symbolName, value)
            symbolName = char(symbolName);
            if isempty(regexp(lower(symbolName), ...
                    ['^gvl_motorruntimeinternal\.' ...
                     'registeredreferencevalid\[[1-4]\]$'], 'once'))
                error('copley:AdsClient:InvalidReferenceValidSymbol', ...
                    'Refusing reference-valid write to %s.', symbolName);
            end
            obj.writeSymbolValue(symbolName, logical(value));
        end

        function writeMotorCalibration(obj, symbolName, value)
            % Backward-compatible method name for callers being migrated.
            obj.writeMotorReference(symbolName, value);
        end
    end

    methods (Access = private)
        function writeSymbolValue(obj, symbolName, value)
            if obj.DryRun
                obj.Symbols(symbolName) = value;
                return;
            end
            value = localPackKnownSymbol(symbolName, value);
            if ~isempty(obj.PlcPort) && ismethod(obj.PlcPort, 'Write')
                obj.PlcPort.Write(symbolName, value);
            elseif ismethod(obj.Ads, 'WriteSymbol')
                obj.Ads.WriteSymbol(symbolName, value);
            elseif ismethod(obj.Ads, 'writeSymbol')
                obj.Ads.writeSymbol(symbolName, value);
            else
                error('copley:AdsClient:UnsupportedApi', ...
                    'Installed TE1410 ADS object does not expose a known symbol write method.');
            end
        end
    end

end

function value = localGet(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end

function localSetupTe14xx()
persistent didSetup
if ~isempty(didSetup) && didSetup
    return;
end
if exist('TwinCAT.ADS.Port', 'class') ~= 8
    setupPath = 'C:\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\SetupTE14xx.p';
    if exist(setupPath, 'file')
        run(setupPath);
    end
end
didSetup = true;
end

function value = localPackKnownSymbol(symbolName, value)
if ~isstruct(value)
    return;
end
name = lower(char(symbolName));
if ~isempty(strfind(name, 'gvl_experimentsequencer.command'))
    value = localPackCommandMailbox(value);
elseif ~isempty(strfind(name, 'gvl_experimentsequencer.protocolparams'))
    value = localPackProtocolParams(value);
elseif ~isempty(strfind(name, 'gvl_experimentsequencer.heartbeat'))
    value = localPackHeartbeat(value);
elseif ~isempty(regexp(name, ['^gvl_motorruntimeinternal\.' ...
        '(registeredreference|commissioningreference)\[[1-4]\]$'], ...
        'once'))
    value = copley.infra.packMotorCalibration(value);
end
end

function value = localUnpackKnownSymbol(symbolName, value)
if ~isa(value, 'uint8')
    return;
end
name = lower(char(symbolName));
if strcmp(name, 'gvl_experimentsequencer.taskperiod_s')
    value = localGetDouble(value, 1);
elseif ~isempty(regexp(name, ['^gvl_motorruntime(?:internal\.' ...
        'commissioningcommand|\.command)\.controlword$'], 'once'))
    value = localGetUint16(value, 1);
elseif ~isempty(regexp(name, ['^gvl_motorruntimeinternal\.' ...
        '(registeredreference|commissioningreference)\[[1-4]\]\.' ...
        'reference_position_count$'], 'once'))
    value = localGetInt32(value, 1);
elseif ~isempty(regexp(name, ['^gvl_motorruntimeinternal\.' ...
        '(registeredreference|commissioningreference)\[[1-4]\]\.' ...
        'reference_commutation_angle$'], 'once'))
    value = localGetUint16(value, 1);
elseif ~isempty(regexp(name, ['^gvl_motorruntimeinternal\.' ...
        '(registeredreference|commissioningreference)\[[1-4]\]\.' ...
        'electrical_direction$'], 'once'))
    value = localGetInt16(value, 1);
elseif ~isempty(strfind(name, 'gvl_experimentsequencer.status'))
    value = localUnpackSequencerStatus(value);
elseif ~isempty(strfind(name, 'gvl_motorruntime.status'))
    value = localUnpackMotorDriverStatus(value);
elseif ~isempty(strfind(name, 'gvl_motorruntimeinternal.feedback')) ...
        || ~isempty(strfind(name, 'gvl_motorruntime.feedback'))
    value = localUnpackMotorFeedback(value);
elseif ~isempty(regexp(name, ['^gvl_motorruntimeinternal\.' ...
        '(registeredreference|commissioningreference)\[[1-4]\]$'], ...
        'once'))
    value = localUnpackMotorReference(value);
elseif ~isempty(strfind(name, 'gvl_experimentsequencer.command'))
    value = localUnpackCommandMailbox(value);
end
end

function value = localUnpackMotorReference(bytes)
bytes = uint8(bytes(:));
if numel(bytes) < 8
    value = [];
    return;
end
value = struct();
value.reference_position_count = localGetInt32(bytes, 1);
value.reference_commutation_angle = localGetUint16(bytes, 5);
value.electrical_direction = localGetInt16(bytes, 7);
end

function bytes = localPackCommandMailbox(s)
bytes = zeros(1, 108, 'uint8');
bytes = localPutUint16(bytes, 1, localStructField(s, 'command_id', 0));
bytes = localPutUint32(bytes, 5, localStructField(s, 'request_id', 0));
bytes = localPutUint32(bytes, 9, localStructField(s, 'lease_id', 0));
bytes = localPutUint16(bytes, 13, localStructField(s, 'protocol_id', 0));
bytes = localPutUint32(bytes, 17, localStructField(s, 'last_accepted_request_id', 0));
bytes = localPutUint32(bytes, 21, localStructField(s, 'last_rejected_request_id', 0));
bytes = localPutString(bytes, 25, 81, localStructField(s, 'rejection_reason', ''));
end

function bytes = localPackHeartbeat(s)
bytes = zeros(1, 8, 'uint8');
bytes = localPutUint32(bytes, 1, localStructField(s, 'lease_id', 0));
bytes = localPutUint32(bytes, 5, localStructField(s, 'counter', 0));
end

function bytes = localPackProtocolParams(s)
bytes = zeros(1, 192, 'uint8');
bytes = localPutUint16(bytes, 1, localStructField(s, 'axis_index', 1));
bytes = localPutInt32(bytes, 5, localStructField(s, 'position_raw_zero', 0));
bytes = localPutDouble(bytes, 9, localStructField(s, 'position_zero_m', 0.0));
bytes = localPutDouble(bytes, 17, localStructField(s, 'position_m_per_count', 1.0e-7));
bytes = localPutDouble(bytes, 25, localStructField(s, 'velocity_mps_per_count', 1.0e-6));
bytes = localPutDouble(bytes, 33, localStructField(s, 'x_soft_min_m', -0.01));
bytes = localPutDouble(bytes, 41, localStructField(s, 'x_soft_max_m', 0.01));
bytes = localPutDouble(bytes, 49, localStructField(s, 'max_velocity_mps', 0.02));
bytes = localPutInt16(bytes, 57, localStructField(s, 'max_target_count', 50));
bytes = localPutDouble(bytes, 65, localStructField(s, 'current_ramp_count_per_s', 500.0));
bytes = localPutDouble(bytes, 73, localStructField(s, 'task_period_s', 0.000125));
bytes = localPutDouble(bytes, 81, localStructField(s, 'settle_time_s', 0.05));
bytes = localPutDouble(bytes, 89, localStructField(s, 'pulse_time_s', 0.05));
bytes = localPutDouble(bytes, 97, localStructField(s, 'post_time_s', 0.05));
bytes = localPutDouble(bytes, 105, localStructField(s, 'timeout_s', 10.0));
bytes = localPutDouble(bytes, 113, localStructField(s, 'angle_start_rad', 0.0));
bytes = localPutDouble(bytes, 121, localStructField(s, 'angle_step_rad', 0.5235987755982988));
bytes = localPutUint16(bytes, 129, localStructField(s, 'angle_count', 12));
bytes = localPutUint16(bytes, 131, localStructField(s, 'protocol2_repeat_count', 2));
bytes = localPutDouble(bytes, 137, localStructField(s, 'protocol2_vmax_mps', 0.002));
bytes = localPutDouble(bytes, 145, localStructField(s, 'protocol2_accel_time_s', 0.05));
bytes = localPutDouble(bytes, 153, localStructField(s, 'protocol2_const_time_s', 0.0));
bytes = localPutDouble(bytes, 161, localStructField(s, 'protocol2_pause_time_s', 0.050));
bytes = localPutDouble(bytes, 169, localStructField(s, 'speed_kp_count_per_mps', 20000.0));
bytes = localPutDouble(bytes, 177, localStructField(s, 'speed_ki_count_per_m', 0.0));
bytes = localPutInt16(bytes, 185, localStructField(s, 'speed_integral_limit_count', 200));
end

function s = localUnpackSequencerStatus(bytes)
s = struct();
s.done = logical(localByte(bytes, 1));
s.fault = logical(localByte(bytes, 2));
s.fault_id = localGetUint32(bytes, 5);
end

function s = localUnpackMotorDriverStatus(bytes)
s = struct();
s.StatusWord = localGetUint16(bytes, 1);
s.PositionActualValue = localGetInt32(bytes, 5);
s.VelocityActualValue = localGetInt32(bytes, 9);
s.TorqueActualValue = localGetInt16(bytes, 13);

s.encoder_position_raw = s.PositionActualValue;
s.encoder_velocity_raw = s.VelocityActualValue;
s.copley_statusword = s.StatusWord;
s.copley_actual_current_count = s.TorqueActualValue;
s.fault = bitand(uint16(s.StatusWord), uint16(hex2dec('0008'))) ~= 0;
s.fault_id = uint32(0);
end

function s = localUnpackMotorFeedback(bytes)
s = struct();
s.encoder_position_raw = localGetInt32(bytes, 1);
s.encoder_velocity_raw = localGetInt32(bytes, 5);
s.copley_statusword = localGetUint16(bytes, 9);
s.copley_actual_current_count = localGetInt16(bytes, 11);
s.output_torque_count = localGetInt16(bytes, 13);
s.fault_id = localGetUint32(bytes, 17);
s.fault = s.fault_id ~= 0;
end

function s = localUnpackCommandMailbox(bytes)
s = struct();
s.command_id = localGetUint16(bytes, 1);
s.request_id = localGetUint32(bytes, 5);
s.lease_id = localGetUint32(bytes, 9);
s.protocol_id = localGetUint16(bytes, 13);
s.last_accepted_request_id = localGetUint32(bytes, 17);
s.last_rejected_request_id = localGetUint32(bytes, 21);
s.rejection_reason = localGetString(bytes, 25, 81);
end

function value = localStructField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end

function bytes = localPutUint16(bytes, pos, value)
bytes(pos:pos+1) = typecast(uint16(value), 'uint8');
end

function bytes = localPutInt16(bytes, pos, value)
bytes(pos:pos+1) = typecast(int16(value), 'uint8');
end

function bytes = localPutUint32(bytes, pos, value)
bytes(pos:pos+3) = typecast(uint32(value), 'uint8');
end

function bytes = localPutInt32(bytes, pos, value)
bytes(pos:pos+3) = typecast(int32(value), 'uint8');
end

function bytes = localPutDouble(bytes, pos, value)
bytes(pos:pos+7) = typecast(double(value), 'uint8');
end

function bytes = localPutString(bytes, pos, byteCount, value)
chars = uint8(char(value));
chars = chars(1:min(numel(chars), byteCount - 1));
bytes(pos:pos+byteCount-1) = uint8(0);
bytes(pos:pos+numel(chars)-1) = chars;
end

function value = localGetUint16(bytes, pos)
value = typecast(uint8(bytes(pos:pos+1)), 'uint16');
end

function value = localGetInt16(bytes, pos)
value = typecast(uint8(bytes(pos:pos+1)), 'int16');
end

function value = localGetUint32(bytes, pos)
value = typecast(uint8(bytes(pos:pos+3)), 'uint32');
end

function value = localGetInt32(bytes, pos)
value = typecast(uint8(bytes(pos:pos+3)), 'int32');
end

function value = localGetDouble(bytes, pos)
value = typecast(uint8(bytes(pos:pos+7)), 'double');
end

function value = localByte(bytes, pos)
value = uint8(bytes(pos));
end

function value = localGetString(bytes, pos, byteCount)
raw = uint8(bytes(pos:pos+byteCount-1));
zero = find(raw == 0, 1);
if ~isempty(zero)
    raw = raw(1:zero-1);
end
value = char(raw);
end
