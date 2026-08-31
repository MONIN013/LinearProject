function output = lsimInvModel(model, signal)
%LSIMINVMODEL Apply the stable inverse of each nominal-model stage.
signal = signal(:);
output = srinv(model.base, signal);

unity = tf(1, 1, model.Ts);
if isfield(model, "lpf") && ~isequal(model.lpf, unity)
    output = srinv(model.lpf, output);
end
if isfield(model, "reso")
    for k = 1:numel(model.reso)
        if ~isequal(model.reso(k), unity)
            output = srinv(model.reso(k), output);
        end
    end
end
if model.delay ~= 0
    output = [output(model.delay+1:end); zeros(model.delay, 1)];
end
end
