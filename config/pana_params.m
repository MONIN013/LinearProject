clear; close all;
%%
MAX_INPUT=2.0; %maximum input (rated current) [A]
ENCODER_RESOLUTION = 100e-9; % 100 nm in meters
VELOCITY_RESOLUTION = 1e-6; % PLC VelocityActualValue is 1 um/s per count
PULSE_TO_WIDTH = ENCODER_RESOLUTION; % Conversion factor from pulses to width
CURRENT_TO_UNIT = 1000/MAX_INPUT; % Conversion factor from current to unit
OPERATION_MODE = 10; % Cyclic synchronous torque mode
MAX_FORCE = 2000;
MAX_SPEED = 10000;


configRoot = fileparts(mfilename("fullpath"));
save(fullfile(configRoot, "data", "pana_params.mat"))
