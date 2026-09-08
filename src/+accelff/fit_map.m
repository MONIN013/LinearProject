function model = fit_map(obs, grid, o)
%FIT_MAP i = g(x)+b(x)*v+c(x)*sign(v)+alpha(x)*a, in amperes.
% Fit TRAIN profiles only. Invalid locations stay NaN; regularization never
% disguises rank deficiency. No physical mass or thrust constant is assumed.
validateattributes(grid,{'double'},{'column','finite','increasing'});
assert(all(string(obs.split)=="train"),'accelff:Holdout', ...
    'Pass training observations only; do not tune against validation/test.');
assert(all(isfinite([obs.bin;obs.v;obs.a;obs.current])) && ...
    all(obs.bin==fix(obs.bin) & obs.bin>=1 & obs.bin<=numel(grid)), ...
    'accelff:Observation','Invalid position index or nonfinite observation.');
assert(all(abs(obs.v)>=o.velocity_floor),'accelff:Stopped','Stopped observations are excluded.');
for name={'minimum_profiles','minimum_dynamic_profiles','minimum_observations','minimum_residual_df'}
    validateattributes(o.(name{1}),{'double'},{'scalar','integer','positive'});
end
validateattributes(o.acceleration_threshold,{'double'},{'scalar','finite','positive'});
validateattributes(o.maximum_condition,{'double'},{'scalar','finite','>=',1});
validateattributes(o.minimum_partial_leverage,{'double'},{'scalar','>',0,'<',1});
ng=numel(grid); beta=nan(ng,4); bounds=nan(ng,4); valid=false(ng,1);
diag=repmat(struct('reason',"no_data",'rank',0,'condition',Inf, ...
    'partial_leverage',0,'profiles',0,'dynamic_profiles',0,'residual_df',0),ng,1);
for k=1:ng
    z=obs(obs.bin==k,:);
    if isempty(z), continue; end
    % Average repeats BEFORE counting independent observations. Otherwise a
    % thousand repeated runs could falsely pass the excitation/DOF gates.
    groups=findgroups(string(z.profile_id),sign(z.v));
    v=splitapply(@mean,z.v,groups); a=splitapply(@mean,z.a,groups);
    y=splitapply(@mean,z.current,groups);
    names=splitapply(@(s)s(1),string(z.profile_id),groups);
    X=[ones(size(v)),v,sign(v),a];
    scale=sqrt(mean(X.^2,1)); scale(scale==0)=1; Z=X./scale;
    d=diag(k); d.profiles=numel(unique(names));
    d.dynamic_profiles=numel(unique(names(abs(a)>o.acceleration_threshold)));
    d.rank=rank(Z); d.residual_df=size(Z,1)-d.rank;
    d.condition=cond(Z);
    residual=Z(:,4)-Z(:,1:3)*(pinv(Z(:,1:3))*Z(:,4));
    d.partial_leverage=sum(residual.^2)/max(sum(Z(:,4).^2),eps);
    if d.profiles<o.minimum_profiles || d.dynamic_profiles<o.minimum_dynamic_profiles
        d.reason="insufficient_profiles";
    elseif size(Z,1)<o.minimum_observations || d.residual_df<o.minimum_residual_df
        d.reason="insufficient_observations";
    elseif d.rank<4 || d.condition>o.maximum_condition
        d.reason="rank_or_condition";
    elseif d.partial_leverage<o.minimum_partial_leverage
        d.reason="acceleration_confounded";
    else
        beta(k,:)=(Z\y)'./scale;
        bounds(k,:)=[min(v),max(v),min(a),max(a)];
        valid(k)=true; d.reason="dynamic";
    end
    diag(k)=d;
end
model=struct('schema_version',1,'grid',grid,'coefficients',beta, ...
    'coefficient_order',["g","b","c","alpha"],'valid',valid, ...
    'bounds',bounds,'diagnostics',diag,'options',o, ...
    'training_profiles',unique(string(obs.profile_id)), ...
    'current_kind',"command_A",'hardware_approved',false);
end
