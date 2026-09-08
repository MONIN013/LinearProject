function tests = test_feedforward_experiment
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
end

function testLoaderAcceptsFeedforwardSchemaV1(testCase)
[dataDir, cleanup] = localTempDirectory();
samplePeriod = 0.000125;
expected = reshape(1:40, 10, 4);
tc_yout = localTwinCATOutput(expected, 12, samplePeriod);
save(fullfile(dataDir, "measurement_part0.mat"), "tc_yout");

[measurement, timeRaw, timeElapsed, matPath, metadata] = ...
    load_latest_twincat_measurement(dataDir, samplePeriod);

verifyEqual(testCase, measurement, expected);
verifyEqual(testCase, timeRaw, 12 + (0:3) * samplePeriod, ...
    "AbsTol", eps(12));
verifyEqual(testCase, timeElapsed, (0:3) * samplePeriod, ...
    "AbsTol", eps(12));
verifyEqual(testCase, metadata.schema_version, uint16(1));
verifyEqual(testCase, metadata.schema_name, "feedforward_v1");
verifyEqual(testCase, metadata.signal_count, uint16(10));
verifyEqual(testCase, metadata.signal_names, localFeedforwardSignalNames());
verifyEqual(testCase, metadata.observed_sample_period_s, samplePeriod, ...
    "AbsTol", 1e-12);
verifyEqual(testCase, string(matPath), ...
    fullfile(dataDir, "measurement_part0.mat"));
delete(cleanup);
end

function testLoaderRejectsSamplePeriodMismatch(testCase)
[dataDir, cleanup] = localTempDirectory();
configuredPeriod = 1/8000;
actualPeriod = 1/4000;
tc_yout = localTwinCATOutput(zeros(10, 4), 0, actualPeriod);
save(fullfile(dataDir, "measurement_part0.mat"), "tc_yout");

verifyError(testCase, ...
    @()load_latest_twincat_measurement(dataDir, configuredPeriod), ...
    "NikonMotor:MeasurementSamplePeriodMismatch");
delete(cleanup);
end

function testDefaultTrajectoryShape(testCase)
assumeTrue(testCase, license("test", "Symbolic_Toolbox"), ...
    "Symbolic Math Toolbox is required by TrajectTools.");

traj = generateMyProfile_TrajectTools( ...
    0, 1.4, 0.5, 1.0, 1.25e-4, 2.0, 1.5, 1.5);

fields = ["time", "pos", "vel", "acc", "jerk", "snap"];
for field = fields
    verifySize(testCase, traj.(field), [92801, 1]);
end
verifyEqual(testCase, traj.pos(1), 0, "AbsTol", 1e-12);
verifyEqual(testCase, max(traj.pos), 1.4, "AbsTol", 1e-10);
verifyEqual(testCase, traj.pos(end), 0, "AbsTol", 1e-10);
end

function testTunableModelFeedforwardSignalOrder(testCase)
modelFile = fullfile(testCase.TestData.repoRoot, ...
    "simulink", "linear_exp_tunable_2025a.slx");
modelName = "linear_exp_tunable_2025a";
load_system(modelFile);
cleanup = onCleanup(@()localCloseModel(modelName));

muxPath = modelName + "/Mux2";
verifyEqual(testCase, string(get_param(muxPath, "Inputs")), "10");

connectivity = get_param(muxPath, "PortConnectivity");
actual = strings(1, 10);
for i = 1:10
    actual(i) = localSourceSignalName( ...
        connectivity(i).SrcBlock, connectivity(i).SrcPort);
end

expected = [ ...
    "count", "error", "input", "vel", "position", ...
    "torque", "ff", "absolute position", "ref", "rf"];
verifyEqual(testCase, actual, expected);
delete(cleanup);
end

function testTunableTrajectoryPackingKeepsGeneratedDimensionsFixed(testCase)
capacity = 8;
reference = [1, 2, 3];
feedforward = [4, 5, 6];

values = prepare_tunable_trajectory_parameters( ...
    reference, feedforward, capacity);

verifyEqual(testCase, values.p_count, 3);
verifyEqual(testCase, values.p_ref, [1; 2; 3; 3; 3; 3; 3; 3]);
verifyEqual(testCase, values.p_ff, [4; 5; 6; 6; 6; 6; 6; 6]);
end

function testTunableTrajectoryPackingRejectsOversizeInput(testCase)
verifyError(testCase, ...
    @()prepare_tunable_trajectory_parameters(1:5, 6:10, 4), ...
    "NikonMotor:TrajectoryBufferExceeded");
end

function testTunableModelUsesFixedRuntimeTrajectoryParameters(testCase)
modelFile = fullfile(testCase.TestData.repoRoot, ...
    "simulink", "linear_exp_tunable_2025a.slx");
modelName = "linear_exp_tunable_2025a";
load_system(modelFile);
cleanup = onCleanup(@()localCloseModel(modelName));

mdlWks = get_param(modelName, "ModelWorkspace");
expectedCapacity = tunable_trajectory_buffer_capacity();
parameterHeader = fileread(fullfile(testCase.TestData.repoRoot, ...
    "src", "linear_exp_tunable_2025a_parameters.h"));
verifySubstring(testCase, parameterHeader, ...
    sprintf("p_ref[%d]", expectedCapacity));
verifySubstring(testCase, parameterHeader, ...
    sprintf("p_ff[%d]", expectedCapacity));
for name = ["p_ref", "p_ff"]
    parameter = mdlWks.evalin(name);
    verifyClass(testCase, parameter, "Simulink.Parameter");
    verifySize(testCase, parameter.Value, [expectedCapacity, 1]);
    verifyEqual(testCase, ...
        string(parameter.CoderInfo.StorageClass), "ImportedExtern");
end
countParameter = mdlWks.evalin("p_count");
verifyClass(testCase, countParameter, "Simulink.Parameter");
verifyEqual(testCase, string(get_param( ...
    modelName, "TcCom_ParametersInitValues")), "off");
verifyEqual(testCase, string(get_param( ...
    modelName, "TcCom_ExtModeRtAllowForParameterChange")), "on");
verifyEqual(testCase, string(get_param( ...
    modelName, "TcProject_UseLLVMCodeInfo")), "on");
verifyEqual(testCase, string(get_param( ...
    modelName, "TcProject_PreCodeGenerationCallbackFcn")), ...
    "compact_tunable_trajectory_tlc_export");
verifySubstring(testCase, string(get_param( ...
    modelName, "CustomHeaderCode")), ...
    "linear_exp_tunable_2025a_parameters.h");

countBlock = find_system(modelName + "/Reference", ...
    "LookUnderMasks", "all", "FollowLinks", "on", ...
    "MaskType", "Compare To Constant");
verifyNumElements(testCase, countBlock, 1);
verifyEqual(testCase, string(get_param(countBlock{1}, "const")), "p_count");
delete(cleanup);
end

function testTunableModelGatesInactiveTorqueAtRatedCurrent(testCase)
modelFile = fullfile(testCase.TestData.repoRoot, ...
    "simulink", "linear_exp_tunable_2025a.slx");
modelName = "linear_exp_tunable_2025a";
load_system(modelFile);
cleanup = onCleanup(@()localCloseModel(modelName));

verifyEqual(testCase, string(get_param( ...
    modelName + "/FB flag", "Gain")), "feedbackFlag*p_active");
verifyEqual(testCase, string(get_param( ...
    modelName + "/linear system/Saturation", "UpperLimit")), "MAX_INPUT");
verifyEqual(testCase, string(get_param( ...
    modelName + "/linear system/Saturation", "LowerLimit")), "-MAX_INPUT");
verifyEqual(testCase, string(get_param( ...
    modelName + "/linear system/Gain1", "Gain")), ...
    "CURRENT_TO_UNIT*p_active");
delete(cleanup);
end

function testModelsExposeOneVirtualCstTorqueCommand(testCase)
parameters = load(fullfile(testCase.TestData.repoRoot, ...
    "config", "data", "pana_params.mat"));
verifyFalse(testCase, isfield(parameters, "CORE_TORQUE_WINDOWS_COUNTS"));

modelFiles = [ ...
    fullfile(testCase.TestData.repoRoot, ...
        "simulink", "linear_exp_2025a.slx"), ...
    fullfile(testCase.TestData.repoRoot, ...
        "simulink", "linear_exp_tunable_2025a.slx")];
modelNames = ["linear_exp_2025a", "linear_exp_tunable_2025a"];
systemNames = ["Linear System", "linear system"];

for modelIndex = 1:numel(modelNames)
    load_system(modelFiles(modelIndex));
    cleanup = onCleanup(@()localCloseModel(modelNames(modelIndex)));
    systemPath = modelNames(modelIndex) + "/" + systemNames(modelIndex);
    torqueOutputs = find_system(systemPath, "SearchDepth", 1, ...
        "MaskType", "TC Module Output");
    verifyNumElements(testCase, torqueOutputs, 1);
    verifyEqual(testCase, string(torqueOutputs{1}), ...
        systemPath + "/Target Torque");
    verifyEqual(testCase, localInputSourceName(torqueOutputs{1}, 1), ...
        "Data Type Conversion");
    % Physical core selection belongs exclusively to CopleyTest MotorRuntime.
    verifyEmpty(testCase, find_system(systemPath, "SearchDepth", 1, ...
        "RegExp", "on", "Name", "^(Core Window|Torque Gate) Axis "));
    delete(cleanup);
end
end

function testModelsUseVelocityCountResolution(testCase)
modelFiles = [ ...
    fullfile(testCase.TestData.repoRoot, ...
        "simulink", "linear_exp_2025a.slx"), ...
    fullfile(testCase.TestData.repoRoot, ...
        "simulink", "linear_exp_tunable_2025a.slx")];
modelNames = ["linear_exp_2025a", "linear_exp_tunable_2025a"];
gainPaths = [ ...
    modelNames(1) + "/Linear System/Gain2", ...
    modelNames(2) + "/linear system/Gain2"];

for i = 1:numel(modelNames)
    load_system(modelFiles(i));
    cleanup = onCleanup(@()localCloseModel(modelNames(i)));
    verifyEqual(testCase, string(get_param(gainPaths(i), "Gain")), ...
        "VELOCITY_RESOLUTION");
    delete(cleanup);
end

paramsSource = fileread(fullfile(testCase.TestData.repoRoot, ...
    "config", "pana_params.m"));
verifyNotEmpty(testCase, regexp(paramsSource, ...
    'VELOCITY_RESOLUTION\s*=\s*1e-6\s*;', 'once'));
end

function names = localFeedforwardSignalNames()
names = [ ...
    "count", ...
    "tracking_error_m", ...
    "control_current_A", ...
    "velocity_m_per_s", ...
    "position_m", ...
    "torque_actual_A", ...
    "feedforward_current_A", ...
    "absolute_position_m", ...
    "reference_m", ...
    "quantized_reference_m"];
end

function name = localSourceSignalName(sourceBlock, sourcePort)
portHandles = get_param(sourceBlock, "PortHandles");
lineHandle = get_param(portHandles.Outport(sourcePort + 1), "Line");
name = string(get_param(lineHandle, "Name"));
if strlength(name) > 0
    return
end

outports = find_system(sourceBlock, "SearchDepth", 1, ...
    "FindAll", "on", "BlockType", "Outport");
portNumbers = arrayfun(@(handle)str2double(get_param(handle, "Port")), outports);
name = string(get_param(outports(portNumbers == sourcePort + 1), "Name"));
end

function name = localInputSourceName(blockPath, portNumber)
portHandles = get_param(blockPath, "PortHandles");
lineHandle = get_param(portHandles.Inport(portNumber), "Line");
sourceBlock = get_param(lineHandle, "SrcBlockHandle");
name = string(get_param(sourceBlock, "Name"));
end

function tc_yout = localTwinCATOutput(data, startTime, samplePeriod)
sampleCount = size(data, 2);
tc_yout = repmat(struct("time", 0, ...
    "data", zeros(size(data, 1), 1)), 1, sampleCount);
for i = 1:sampleCount
    tc_yout(i).time = startTime + (i - 1) * samplePeriod;
    tc_yout(i).data = data(:, i);
end
end

function [directory, cleanup] = localTempDirectory()
directory = string(tempname);
mkdir(directory);
cleanup = onCleanup(@()rmdir(directory, "s"));
end

function localCloseModel(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end
