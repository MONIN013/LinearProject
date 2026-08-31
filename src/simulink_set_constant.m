% function simulink_set_constant(block, signal)  
% if length(signal) > 1
% set_param(block,"Value",strcat("[",num2str(signal(:)'),"]'"));
% else
% set_param(block,"Value",num2str(signal));
% end
% 
function simulink_set_constant(block, signal)
    if numel(signal) > 1
        s = [mat2str(signal(:).', 17) ''''];
        set_param(block, 'Value', s);
    else
        set_param(block, 'Value', sprintf('%.17g', signal));
    end
end
% 
% function simulink_set_constant(block, signal, varName)
%     if nargin < 3, varName = 'const_signal'; end
%     assignin('base', varName, signal(:));          % ��x�N�g���Ŋi�[
%     set_param(block, 'Value', varName);            % �ϐ��Q�Ƃɂ���
% end
