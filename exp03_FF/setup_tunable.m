%% Build the tunable external-mode model
projectRoot = fileparts(fileparts(mfilename("fullpath")));
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(projectRoot, "Cache"), ...
    "CodeGenFolder", fullfile(projectRoot, "CodeGen"), "createDir", true);
load_system(fullfile(projectRoot, ModelName))
[~, model] = fileparts(ModelName);
model = string(model);
bufferCapacity = tunable_trajectory_buffer_capacity();
params = struct( ...
    "p_ref", zeros(bufferCapacity, 1), ...
    "p_ff", zeros(bufferCapacity, 1), ...
    "p_count", 1, ...
    "p_active", 0, ...
    "p_servo", 0);
blocks = struct( ...
    "p_ref", BlockPaths{Index_ref}, ...
    "p_ff", BlockPaths{Index_ff}, ...
    "p_active", BlockPaths{Index_active}, ...
    "p_servo", BlockPaths{Index_servo});

set_param(model, "DefaultParameterBehavior", "Tunable");
% External Mode supplies all experiment parameters after connection. Omitting
% their default values from the TMC prevents TE1400 from analysing hundreds of
% thousands of array initializers during every build.
set_param(model, "TcCom_ParametersInitValues", "off");
set_param(model, "TcCom_ParametersDataAccess", "Internal DataArea");
set_param(model, "TcCom_ParametersCreateSymbols", "on");
set_param(model, "TcProject_UseLLVMCodeInfo", "on");
set_param(model, "TcProject_PreCodeGenerationCallbackFcn", ...
    "compact_tunable_trajectory_tlc_export");
set_param(model, "TcProject_PostCodeGenerationCallbackFcn", "");
set_param(model, "CustomHeaderCode", ...
    "#include ""linear_exp_tunable_2025a_parameters.h""");
set_param(model, "CustomSource", ...
    fullfile(projectRoot, "src", "linear_exp_tunable_2025a_parameters.cpp"));
set_param(model, "CustomInclude", fullfile(projectRoot, "src"));

countBlock = find_system(model + "/Reference", ...
    "LookUnderMasks", "all", "FollowLinks", "on", ...
    "MaskType", "Compare To Constant");
assert(numel(countBlock) == 1, ...
    "NikonMotor:ReferenceCountBlockNotFound", ...
    "Expected exactly one Compare To Constant block in Reference.");
set_param(countBlock{1}, "const", "p_count");

mdlWks = get_param(model, "ModelWorkspace");
names = fieldnames(params);
for k = 1:numel(names)
    name = names{k};
    value = params.(name);
    if ~isscalar(value), value = value(:); end
    if mdlWks.hasVariable(name)
        parameter = mdlWks.evalin(name);
        if isa(parameter, "Simulink.Parameter")
            parameter.Value = value;
        else
            parameter = Simulink.Parameter(value);
        end
    else
        parameter = Simulink.Parameter(value);
    end
    if any(strcmp(name, {'p_ref', 'p_ff'}))
        parameter.CoderInfo.StorageClass = "ImportedExtern";
    else
        parameter.CoderInfo.StorageClass = "Auto";
    end
    assignin(mdlWks, name, parameter);
    if any(strcmp(name, {'p_ref', 'p_ff'}))
        assert(strcmp(parameter.CoderInfo.StorageClass, "ImportedExtern"), ...
            "NikonMotor:TunableStorageClassMismatch", ...
            "Unexpected storage class for %s.", name);
    end
    if isfield(blocks, name)
        set_param(blocks.(name), "Value", name);
    end
end

save_system(model)
slbuild(model)
builtSamplePeriod = Ts;
builtModel = model;
builtAt = datetime("now");
save(fullfile(projectRoot, "config", "data", "tunable_build_info.mat"), ...
    "builtSamplePeriod", "builtModel", "builtAt");
