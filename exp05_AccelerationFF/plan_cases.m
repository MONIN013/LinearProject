function cases = plan_cases()
%PLAN_CASES Predetermined profile-level split and balanced one-shot comparison.
% Durations/warps are candidate shapes, not authorized hardware trajectories.
% Training rows identify the generalized map from CONVERGED ILC teachers.
% Held-out rows compare first-trial transfer of FB/thesis/proposed FF.
profile_id=["train01";"train02";"train03";"train04";"train05";"train06"; ...
    "validation01";"validation02";"test01";"test02"];
duration=[6;6;8;8;10;10;7;9;7.5;9.5];
warp=[-.65;.65;-.65;.65;-.65;.65;-.25;.25;-.4;.4];
split=[repmat("train",6,1);repmat("validation",2,1);repmat("test",2,1)];
cases=table('Size',[0,7],'VariableTypes', ...
    {'string','string','string','double','double','double','string'}, ...
    'VariableNames',{'id','profile_id','split','duration','warp','repeat','method'});
for p=1:numel(profile_id)
    if split(p)=="train"
        % One row represents the accepted teacher extracted from a separate
        % ILC sequence in plan_ilc_sequences. ILC iterations are NOT repeats.
        id=profile_id(p)+"_ilc_teacher";
        cases=[cases;table(id,profile_id(p),split(p),duration(p),warp(p),1,"ilc_teacher", ...
            'VariableNames',cases.Properties.VariableNames)]; %#ok<AGROW>
        continue
    end
    for repeat=1:3
        order=["fb","thesis","acceleration"];
        methods=circshift(order,[0,repeat-1]); % randomization surrogate; never shift a signal
        for method=methods
            id=profile_id(p)+"_r"+repeat+"_"+method;
            cases=[cases;table(id,profile_id(p),split(p),duration(p),warp(p),repeat,method, ...
                'VariableNames',cases.Properties.VariableNames)]; %#ok<AGROW>
        end
    end
end
end
