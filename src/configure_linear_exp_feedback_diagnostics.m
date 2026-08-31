function result = configure_linear_exp_feedback_diagnostics(modelFile)
%CONFIGURE_LINEAR_EXP_FEEDBACK_DIAGNOSTICS Append virtual-CST diagnostics.
%
% The existing seven File Writer inputs are preserved verbatim. Ten private
% MotorRuntime diagnostics are appended as double-precision scalar signals.

if nargin < 1 || strlength(string(modelFile)) == 0
    repoRoot = fileparts(fileparts(mfilename("fullpath")));
    modelFile = fullfile(repoRoot, "simulink", "linear_exp_2025a.slx");
end
modelFile = string(modelFile);
if ~isfile(modelFile)
    error("NikonMotor:ModelNotFound", "Model was not found: %s", modelFile);
end

[modelDir, modelName] = fileparts(modelFile);
addpath(modelDir);
wasLoaded = bdIsLoaded(modelName);
load_system(modelFile);
closeGuard = onCleanup(@()localCloseModel(modelName, wasLoaded));

muxPath = modelName + "/Mux1";
writerPath = modelName + "/TwinCAT File Writer";
diagnosticPath = modelName + "/Virtual CST Diagnostics";
marker = "NikonMotor:VirtualCstFeedbackDiagnostics:v1";

if ~strcmp(get_param(writerPath, "FunctionName"), "TcFileWriter")
    error("NikonMotor:UnexpectedFileWriter", ...
        "Expected a TwinCAT File Writer at %s.", writerPath);
end

existingInputs = str2double(get_param(muxPath, "Inputs"));
if getSimulinkBlockHandle(diagnosticPath) >= 0
    if string(get_param(diagnosticPath, "Tag")) ~= marker
        error("NikonMotor:DiagnosticSubsystemConflict", ...
            "An unrelated block already exists at %s.", diagnosticPath);
    end
    delete_block(diagnosticPath);
    set_param(muxPath, "Inputs", "7");
    existingInputs = 7;
end
if existingInputs ~= 7
    error("NikonMotor:UnexpectedFileWriterSchema", ...
        "Mux1 must contain the original seven inputs before configuration.");
end

originalSources = localMuxSources(muxPath, 7);
if any(strlength(originalSources) == 0)
    error("NikonMotor:DisconnectedLegacySignal", ...
        "All seven legacy File Writer inputs must be connected.");
end

signalNames = [ ...
    "PanasonicPositionRaw", ...
    "PanasonicVelocityRaw", ...
    "PanasonicWcState", ...
    "PanasonicInputToggle", ...
    "CopleyWcState", ...
    "CopleyInputToggle", ...
    "PanasonicStatusWord", ...
    "PanasonicErrorCode", ...
    "TaskCycleTimeExceeded", ...
    "TaskExceedCounter"];
signalTypes = [ ...
    "int32", "int32", ...
    "boolean", "boolean", "boolean", "boolean", ...
    "uint16", "uint16", "boolean", "uint32"];

set_param(muxPath, "Inputs", "17");
add_block("built-in/Subsystem", diagnosticPath, ...
    "Position", [1305 545 1435 805], ...
    "Tag", marker);

templatePath = modelName + "/Linear System/Position actual value";
for i = 1:numel(signalNames)
    y = 35 + (i - 1) * 55;
    inputPath = diagnosticPath + "/" + signalNames(i);
    conversionPath = diagnosticPath + "/" + signalNames(i) + "ToDouble";
    outputPath = diagnosticPath + "/" + signalNames(i) + "Out";

    add_block(templatePath, inputPath, ...
        "Position", [30 y 170 y + 30]);
    set_param(inputPath, ...
        "PortDataType", signalTypes(i), ...
        "Value", "0", ...
        "SampleTime", "-1", ...
        "PortDim", "-1", ...
        "CodeGenConnectType", "DataArea (InputDst)");

    add_block("simulink/Signal Attributes/Data Type Conversion", ...
        conversionPath, ...
        "OutDataTypeStr", "double", ...
        "Position", [220 y 315 y + 30]);
    add_block("simulink/Sinks/Out1", outputPath, ...
        "Port", string(i), ...
        "Position", [375 y + 3 405 y + 17]);

    add_line(diagnosticPath, ...
        signalNames(i) + "/1", signalNames(i) + "ToDouble/1");
    add_line(diagnosticPath, ...
        signalNames(i) + "ToDouble/1", signalNames(i) + "Out/1");
    add_line(modelName, ...
        "Virtual CST Diagnostics/" + string(i), ...
        "Mux1/" + string(7 + i), ...
        "autorouting", "on");
end

updatedSources = localMuxSources(muxPath, 7);
if ~isequal(updatedSources, originalSources)
    error("NikonMotor:LegacySignalOrderChanged", ...
        "The original seven File Writer sources changed unexpectedly.");
end

save_system(modelName);
result = struct();
result.model_file = string(get_param(modelName, "FileName"));
result.schema_version = uint16(3);
result.file_writer_width = uint16(17);
result.legacy_sources = originalSources;
result.diagnostic_signal_names = signalNames;
clear closeGuard
localCloseModel(modelName, wasLoaded);
end

function sources = localMuxSources(muxPath, count)
connectivity = get_param(muxPath, "PortConnectivity");
sources = strings(1, count);
for i = 1:min(count, numel(connectivity))
    if ~isempty(connectivity(i).SrcBlock)
        sources(i) = string(getfullname(connectivity(i).SrcBlock));
    end
end
end

function localCloseModel(modelName, wasLoaded)
if ~wasLoaded && bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end
