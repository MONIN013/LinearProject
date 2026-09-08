classdef FakeLoggerPort < copley.ports.LoggerPort
    properties
        Logs
        DownloadLog = []
        UseRawTables = false
    end

    methods
        function obj = FakeLoggerPort()
            obj.Logs = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function setProtocolLog(obj, protocolId, log)
            obj.Logs(num2str(double(protocolId))) = log;
        end

        function rawLog = downloadProtocol(obj, protocolId, varargin) %#ok<INUSD>
            obj.DownloadLog(end+1, :) = double(protocolId);
            key = num2str(double(protocolId));
            if isKey(obj.Logs, key)
                rawLog = obj.Logs(key);
                return;
            end
            if obj.UseRawTables
                rawLog = localSyntheticProtocolLog(uint16(protocolId));
            else
                rawLog = struct('protocol_id', uint16(protocolId), ...
                    'synthetic', true, 'accepted', true);
            end
        end
    end
end

function rawLog = localSyntheticProtocolLog(protocolId)
theta = 1.25;
switch double(protocolId)
    case 1
        T = localSyntheticProtocol1(theta);
    case 2
        T = localSyntheticProtocol2();
    case 3
        T = localSyntheticProtocol3();
    otherwise
        T = table();
end
rawLog = struct();
rawLog.protocol_id = uint16(protocolId);
rawLog.rawTable = T;
end

function T = localSyntheticProtocol1(theta)
rows = localRows(12 * 2 * 20);
sample = 0;
row = 0;
dt = 0.001;
amp = 1.0e-5;
for angle = 0:11
    alpha = angle * pi / 6;
    response = amp * cos(alpha - theta);
    [rows, sample, row] = localAppendPulse(rows, sample, row, dt, 1, 1, angle, ...
        alpha, response, 200);
    [rows, sample, row] = localAppendPulse(rows, sample, row, dt, 1, 3, angle, ...
        alpha + pi, -response, 200);
end
T = struct2table(rows);
end

function T = localSyntheticProtocol2()
rows = localRows(80 * 2);
sample = 0;
row = 0;
dt = 0.001;
for k = 1:80
    current = 20 + 2 * k;
    [rows, sample, row] = localAppendSample(rows, sample, row, dt, 2, 10, 0, ...
        k, 0.0, 0.0, current, current);
    [rows, sample, row] = localAppendSample(rows, sample, row, dt, 2, 11, 1, ...
        k, -pi/2, 0.0, current, current);
end
T = struct2table(rows);
end

function T = localSyntheticProtocol3()
rows = localRows(20 * 2);
sample = 0;
row = 0;
dt = 0.001;
for k = 1:20
    [rows, sample, row] = localAppendSample(rows, sample, row, dt, 3, 1, 0, ...
        k, 0.0, double(k) * 2.0e-7, 100, 100);
end
for k = 1:20
    [rows, sample, row] = localAppendSample(rows, sample, row, dt, 3, 3, 0, ...
        k, 0.0, 4.0e-6 - double(k) * 2.0e-7, -100, -100);
end
T = struct2table(rows);
end

function [rows, sample, row] = localAppendPulse(rows, sample, row, dt, protocolId, phaseId, angleId, angleRad, dx, iq)
n = 20;
for k = 1:n
    x = (double(k) - 1.0) ./ double(n - 1) .* dx;
    [rows, sample, row] = localAppendSample(rows, sample, row, dt, protocolId, ...
        phaseId, angleId, k, angleRad, x, iq, iq);
end
end

function [rows, sample, row] = localAppendSample(rows, sample, row, dt, protocolId, phaseId, angleId, localIndex, angleRad, x, iq, target)
sample = sample + 1;
row = row + 1;
i = row;
rows.sample_index(i, 1) = uint32(sample - 1);
rows.t_s(i, 1) = double(sample - 1) * dt;
rows.protocol_t_s(i, 1) = rows.t_s(i, 1);
rows.protocol_id(i, 1) = uint16(protocolId);
rows.phase_id(i, 1) = uint16(phaseId);
rows.angle_index(i, 1) = uint16(angleId);
rows.protocol2_local_sample_index(i, 1) = uint16(localIndex);
rows.experiment_angle_rad(i, 1) = angleRad;
rows.x_abs_m(i, 1) = x;
rows.x_ref_traj_m(i, 1) = x;
rows.v_est_mps(i, 1) = 0.0;
rows.v_actual_mps(i, 1) = 0.0;
rows.iq_cmd_count_req_lreal(i, 1) = double(iq);
rows.target_current_count_lreal(i, 1) = double(target);
rows.output_torque_count(i, 1) = int16(target);
rows.actual_current_count(i, 1) = int16(target);
end

function rows = localRows(n)
rows = struct();
rows.sample_index = zeros(n, 1, 'uint32');
rows.t_s = zeros(n, 1);
rows.protocol_t_s = zeros(n, 1);
rows.protocol_id = zeros(n, 1, 'uint16');
rows.phase_id = zeros(n, 1, 'uint16');
rows.angle_index = zeros(n, 1, 'uint16');
rows.protocol2_local_sample_index = zeros(n, 1, 'uint16');
rows.experiment_angle_rad = zeros(n, 1);
rows.x_abs_m = zeros(n, 1);
rows.x_ref_traj_m = zeros(n, 1);
rows.v_est_mps = zeros(n, 1);
rows.v_actual_mps = zeros(n, 1);
rows.iq_cmd_count_req_lreal = zeros(n, 1);
rows.target_current_count_lreal = zeros(n, 1);
rows.output_torque_count = zeros(n, 1, 'int16');
rows.actual_current_count = zeros(n, 1, 'int16');
end
