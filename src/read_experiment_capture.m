function [measurement, axisLog, time] = read_experiment_capture(result, index)
%READ_EXPERIMENT_CAPTURE Reconstruct a packed capture without intermediate MATs.
if ischar(result) || isstring(result), result = load(result); end
capture = result.captures{index};
time = capture.time;
measurement = nan(10,numel(time));
axisLog = [];
for row = 1:10
    stored = find(capture.rows==row);
    field = capture.fields{row};
    if ~isempty(stored)
        measurement(row,:) = capture.data(stored,:);
    elseif startsWith(field,'history.')
        measurement(row,:) = result.history.(extractAfter(field,'history.'))(:,capture.trial)';
    elseif strcmp(field,'measurement')
        measurement(row,:) = result.measurement(row,:);
    elseif ~isempty(field)
        measurement(row,:) = result.(field)(:).';
    end
end
if strcmp(capture.axisSource,'history.allocationLog')
    axisLog = result.history.allocationLog{capture.trial}.axisLog;
elseif strcmp(capture.axisSource,'capture.allocationLog')
    axisLog = capture.allocationLog.axisLog;
elseif ~isempty(capture.axisSource)
    axisLog = result.(capture.axisSource).axisLog;
elseif nnz(capture.rows>=11 & capture.rows<=30)==20 && ~isempty(time)
    axisLog = decode_axis_snapshot(capture.data(capture.rows>=11 & capture.rows<=30,:),result.Ts);
end
end
