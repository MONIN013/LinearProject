function paths = save_experiment_figures(runDir, figures)
%SAVE_EXPERIMENT_FIGURES Export only the figure handles supplied by the experiment.
figures = figures(isgraphics(figures,'figure'));
paths = strings(numel(figures),1);
if isempty(figures), return; end
folder = fullfile(runDir,'figures');
if ~isfolder(folder), mkdir(folder); end
for k = 1:numel(figures)
    paths(k) = string(fullfile(folder,sprintf('figure_%d.png',figures(k).Number)));
    exportgraphics(figures(k),paths(k));
end
end
