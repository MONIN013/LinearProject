function compact_tunable_trajectory_tlc_export(projectExporter)
% Remove unused large startup values before TE1400 imports generated code.
%
% p_ref and p_ff are ImportedExtern buffers. Their storage is provided by
% linear_exp_tunable_2025a_parameters.cpp and External Mode writes the run
% values after connecting. TE1400 nevertheless serializes their Simulink
% defaults into TlcExport unless they are compacted here. With 100k+ samples
% those redundant values dominate the TwinCAT build time.

[codeDirectory, classConfiguration] = ...
    localCodeDirectory(projectExporter);
if string(classConfiguration.TcCom.ParametersInitValues) ~= "off"
    error("NikonMotor:TunableInitialValuesEnabled", ...
        ["TcCom_ParametersInitValues must be off before trajectory " ...
         "startup values can be removed."]);
end
tlcExportPath = fullfile(codeDirectory, "TlcExport.mat");
if ~isfile(tlcExportPath)
    error("NikonMotor:TlcExportNotFound", ...
        "TE1400 TLC export was not found: %s", tlcExportPath);
end

loaded = load(tlcExportPath, "TlcExport");
tlcExport = loaded.TlcExport;
names = {'p_ref', 'p_ff'};
for k = 1:numel(names)
    name = names{k};
    if ~isKey(tlcExport.Variables, name)
        error("NikonMotor:TunableVariableNotExported", ...
            "TE1400 TLC export does not contain %s.", name);
    end
    variable = tlcExport.Variables(name);
    if ~isfield(variable, "IsGlobalVar") || ~variable.IsGlobalVar
        error("NikonMotor:TunableVariableNotGlobal", ...
            "%s must remain an ImportedExtern global array.", name);
    end
    if ~isfield(variable, "ParamString") || ...
            string(variable.ParamString) ~= string(name)
        error("NikonMotor:TunableVariableMappingChanged", ...
            "Unexpected TE1400 parameter mapping for %s.", name);
    end
    % TcCom_ParametersInitValues is off, so no startup value is needed.
    % Empty string means "no default" to TE1400 while retaining the type,
    % symbol, data area and External Mode parameter mapping.
    variable.Value = "";
    tlcExport.Variables(name) = variable;
end

TlcExport = tlcExport; %#ok<NASGU>
save(tlcExportPath, "TlcExport");
tlcExport.SaveJson(codeDirectory);
fprintf("Compacted TE1400 startup values for p_ref and p_ff.\n");
end

function [codeDirectory, classConfiguration] = ...
        localCodeDirectory(projectExporter)
configuration = projectExporter.Configuration;
classConfigurations = configuration.ClassExportCfg;
matches = cellfun(@(item)strcmp(string(item.Identifier), ...
    "linear_exp_tunable_2025a"), classConfigurations);
if nnz(matches) ~= 1
    error("NikonMotor:TunableExportConfigurationNotFound", ...
        "Expected one export configuration for linear_exp_tunable_2025a.");
end
classConfiguration = classConfigurations{find(matches, 1)};
codeDirectory = string(classConfiguration.CodegenInfo.CodeDirectory);
end
