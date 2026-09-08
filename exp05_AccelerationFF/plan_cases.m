function cases = plan_cases()
%PLAN_CASES Predetermined profile-level split and balanced held-out comparison.
% Durations/warps are candidate shapes, not authorized hardware trajectories.
% Expand with accelff.profile using the reviewed distance and sample period.
% Three repeats improve repeatability estimates but count as ONE profile.
profile_id=["train01";"train02";"train03";"train04";"train05";"train06"; ...
    "validation01";"validation02";"test01";"test02"];
duration=[6;6;8;8;10;10;7;9;7.5;9.5];
warp=[-.65;.65;-.65;.65;-.65;.65;-.25;.25;-.4;.4];
split=[repmat("train",6,1);repmat("validation",2,1);repmat("test",2,1)];
cases=table('Size',[0,7],'VariableTypes', ...
    {'string','string','string','double','double','double','string'}, ...
    'VariableNames',{'id','profile_id','split','duration','warp','repeat','method'});
for p=1:numel(profile_id)
    for repeat=1:3
        if split(p)=="train"
            methods="fb"; % identify total commanded current from accepted low-error runs
        else
            order=["fb","thesis","acceleration"];
            methods=circshift(order,[0,repeat-1]); % order only, NEVER shift a signal
        end
        for method=methods
            id=profile_id(p)+"_r"+repeat+"_"+method;
            cases=[cases;table(id,profile_id(p),split(p),duration(p),warp(p),repeat,method, ...
                'VariableNames',cases.Properties.VariableNames)]; %#ok<AGROW>
        end
    end
end
end
