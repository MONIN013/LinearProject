%% Experiment sample rate
% Change only this value, then rebuild/deploy the Simulink model and set the
% TwinCAT task cycle to the same period before the next experiment.
sampleRateHz = 4e3; % supported: 4e3 or 8e3
assert(ismember(sampleRateHz, [4e3, 8e3]), ...
    "sampleRateHz must be either 4e3 or 8e3.");
Ts = 1/sampleRateHz;

switch sampleRateHz
    case 4e3
        plantDataFile = "data/plants/4khz/current.mat";
    case 8e3
        plantDataFile = "data/plants/8khz/current.mat";
end
