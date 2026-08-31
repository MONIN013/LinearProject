%% simulation setup
open(ModelName)
model = string(bdroot);
params = struct( ...
    "p_ref",    zeros(N,1), ...
    "p_ff",     zeros(N,1), ...
    "p_active", 0, ...
    "p_servo",  0 );
map = struct( ...
    "p_ref",    BlockPaths{Index_ref}, ...
    "p_ff",     BlockPaths{Index_ff}, ...
    "p_active", BlockPaths{Index_active}, ...
    "p_servo",  BlockPaths{Index_servo} );

set_param(model,"DefaultParameterBehavior","Tunable");

mdlWks = get_param(model,'ModelWorkspace');
fn = fieldnames(params);
for k = 1:numel(fn)
    name = fn{k};
    val  = params.(name);
    if isnumeric(val) && ~isscalar(val), val = val(:); end
    if mdlWks.hasVariable(name)
        v = mdlWks.evalin(name);
        if isa(v,'Simulink.Parameter')
            v.Value = val;
        else
            v = Simulink.Parameter(val);
        end
    else
        v = Simulink.Parameter(val);
    end
    assignin(mdlWks,name,v);
end

keys = fieldnames(map);
for i = 1:numel(keys)
    varName = keys{i};
    paths   = map.(varName);
    if ischar(paths) || isstring(paths), paths = cellstr(string(paths)); end
    for j = 1:numel(paths)
        set_param(paths{j},"Value",varName);
    end
end

slbuild(model)