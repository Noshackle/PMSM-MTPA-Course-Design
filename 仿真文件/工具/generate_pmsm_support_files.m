function generate_pmsm_support_files()
% Recreate missing Signal Editor scenarios and MTPA lookup tables.

modelDir = 'C:/Users/asus/Desktop/PMSM MTPA';
modelName = 'PMSM_MTPA';
modelPath = fullfile(modelDir, [modelName '.slx']);
scenarioPath = fullfile(modelDir, 'scenario.mat');
lookupPath = fullfile(modelDir, 'mtpa_lookup_tables.mat');

stopTime = 5.0;
stepDelay = 0.05;
stepDelta = 1e-4;
speedStepTime = 2.5;
loadStepTime = 2.5;

speedStart = 0;
speedLow = 500;
speedHigh = 1000;
loadLight = 1.0;
loadRated = 2.0;

Scenario1 = buildScenario( ...
    [0; stepDelay; stepDelay + stepDelta; stopTime], ...
    [speedStart; speedStart; speedHigh; speedHigh], ...
    [0; stopTime], ...
    [0; 0]);

Scenario2 = buildScenario( ...
    [0; stepDelay; stepDelay + stepDelta; stopTime], ...
    [speedStart; speedStart; speedHigh; speedHigh], ...
    [0; stopTime], ...
    [loadRated; loadRated]);

Scenario3 = buildScenario( ...
    [0; speedStepTime; speedStepTime + stepDelta; stopTime], ...
    [speedLow; speedLow; speedHigh; speedHigh], ...
    [0; stopTime], ...
    [loadLight; loadLight]);

Scenario4 = buildScenario( ...
    [0; stepDelay; stepDelay + stepDelta; stopTime], ...
    [speedStart; speedStart; speedHigh; speedHigh], ...
    [0; loadStepTime; loadStepTime + stepDelta; stopTime], ...
    [0; 0; loadRated; loadRated]);

save(scenarioPath, 'Scenario1', 'Scenario2', 'Scenario3', 'Scenario4');

Ld = 0.2e-3;
Lq = 0.47e-3;
psi_f = 0.062;
p = 4;
Is_max = 20;
n_pts = 200;

Is_vec = linspace(0, Is_max, n_pts);
dL = Lq - Ld;
id_table = (psi_f - sqrt(psi_f^2 + 8 * dL^2 .* Is_vec.^2)) ./ (4 * dL);
iq_table = sqrt(max(Is_vec.^2 - id_table.^2, 0));
Te_table = 1.5 * p * (psi_f .* iq_table + (Ld - Lq) .* id_table .* iq_table);

save(lookupPath, ...
    'Ld', 'Lq', 'psi_f', 'p', 'Is_max', 'Is_vec', ...
    'Te_table', 'id_table', 'iq_table');

load_system(modelPath);
blockPath = [modelName '/Signal Editor'];
set_param(blockPath, 'FileName', scenarioPath, 'ActiveScenario', 'Scenario4');

loadTablesCmd = strjoin({
    'modelDir = fileparts(get_param(bdroot,''FileName''));'
    'tableFile = fullfile(modelDir,''mtpa_lookup_tables.mat'');'
    'if exist(tableFile,''file'')'
    '  s = load(tableFile,''Te_table'',''id_table'',''iq_table'');'
    '  assignin(''base'',''Te_table'',s.Te_table);'
    '  assignin(''base'',''id_table'',s.id_table);'
    '  assignin(''base'',''iq_table'',s.iq_table);'
    'end'
    }, ' ');

set_param(modelName, 'PostLoadFcn', loadTablesCmd, 'InitFcn', loadTablesCmd);
save_system(modelName, modelPath);

s = load(lookupPath, 'Te_table', 'id_table', 'iq_table');
assignin('base', 'Te_table', s.Te_table);
assignin('base', 'id_table', s.id_table);
assignin('base', 'iq_table', s.iq_table);

scenarioInfo = whos('-file', scenarioPath);
fprintf('scenario.mat variables:\\n');
for k = 1:numel(scenarioInfo)
    fprintf('  %s (%s)\\n', scenarioInfo(k).name, scenarioInfo(k).class);
end

lookupInfo = whos('-file', lookupPath);
fprintf('mtpa_lookup_tables.mat variables:\\n');
for k = 1:numel(lookupInfo)
    fprintf('  %s (%s)\\n', lookupInfo(k).name, lookupInfo(k).class);
end

out = sim(modelName, 'StopTime', '0.1');
fprintf('short simulation status: success, tout end = %.6f s\\n', out.tout(end));

bdclose(modelName);
end

function ds = buildScenario(speedTime, speedData, loadTime, loadData)
ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(speedData, speedTime), 'n_ref');
ds = ds.addElement(timeseries(loadData, loadTime), 'Tm');
end
