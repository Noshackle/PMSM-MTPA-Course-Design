function build_pmsm_taskbook_assets()
% Build task-book simulation assets for the PMSM MTPA course design.

root = 'C:/Users/asus/Desktop/PMSM MTPA';
model = 'PMSM_MTPA';
modelFile = fullfile(root, [model '.slx']);
scenarioFile = fullfile(root, 'scenario.mat');
lookupFile = fullfile(root, 'mtpa_lookup_tables.mat');
assetsDir = fullfile(root, 'report_assets');
figDir = fullfile(assetsDir, 'figures');
simDir = fullfile(assetsDir, 'simulink');
dataDir = fullfile(assetsDir, 'data');
dirs = {assetsDir, figDir, simDir, dataDir};

for k = 1:numel(dirs)
    if ~exist(dirs{k}, 'dir')
        mkdir(dirs{k});
    end
end

if exist(modelFile, 'file')
    backupFile = fullfile(root, ...
        ['PMSM_MTPA_backup_before_taskbook_' datestr(now, 'yyyymmdd_HHMMSS') '.slx']);
    copyfile(modelFile, backupFile);
end

caseDefs = create_scenarios(scenarioFile);
create_lookup_tables(lookupFile);

bdclose('all');
load_system(modelFile);

configure_table_loading(model, lookupFile);
configure_signal_editor(model, scenarioFile);
configure_load_connection(model);
configure_speed_limit(model, 40);
configure_mode_selection(model);
configure_reference_logging(model);
set_param(model, 'StopTime', '1');
save_system(model, modelFile);

metrics = run_cases(root, model, caseDefs, figDir, dataDir);
save(fullfile(dataDir, 'taskbook_metrics.mat'), 'metrics', 'caseDefs');
writetable(struct2table(metrics), fullfile(dataDir, 'taskbook_metrics.csv'), 'Encoding', 'UTF-8');

export_model_shots(model, simDir);

save_system(model, modelFile);
bdclose(model);
end

function caseDefs = create_scenarios(scenarioFile)
t = (0:1e-4:1).';
dt = 1e-4;

profiles = {
    'Scenario1', 3000 * ones(size(t)), 0 * ones(size(t)), ...
        '工况1 空载启动', 0.0, 0.0, 3000.0, 0.0, 0.0;
    'Scenario2', 1000 * ones(size(t)), 5 * ones(size(t)), ...
        '工况2 带载启动', 0.0, 0.0, 1000.0, 5.0, 5.0;
    'Scenario3', 1000 + (t >= 0.5) * 1000, 5 * ones(size(t)), ...
        '工况3 转速阶跃', 0.5, 1000.0, 2000.0, 5.0, 5.0;
    'Scenario4', 1500 * ones(size(t)), 2 + (t >= 0.5) * 8, ...
        '工况4 负载突加', 0.5, 1500.0, 1500.0, 2.0, 10.0;
    'Scenario5', 1500 * ones(size(t)), 8 * ones(size(t)), ...
        '工况5 lookup 对比', 0.0, 1500.0, 1500.0, 8.0, 8.0;
    };

saved = struct();
caseDefs = repmat(struct( ...
    'scenario', '', ...
    'label', "", ...
    'short', "", ...
    'useLookup', 0, ...
    'useMTPA', 1, ...
    'eventTime', 0.0, ...
    'speedStart', 0.0, ...
    'speedEnd', 0.0, ...
    'loadStart', 0.0, ...
    'loadEnd', 0.0), 6, 1);

for k = 1:size(profiles, 1)
    ds = Simulink.SimulationData.Dataset;
    nRef = timeseries(profiles{k, 2}, t);
    nRef.Name = 'n_ref';
    loadTs = timeseries(profiles{k, 3}, t);
    loadTs.Name = 'Tm';
    ds = ds.addElement(nRef, 'n_ref');
    ds = ds.addElement(loadTs, 'Tm');
    saved.(profiles{k, 1}) = ds;
end

save(scenarioFile, '-struct', 'saved');

base = {
    1, 0, 1, "case1_no_load";
    2, 0, 1, "case2_loaded";
    3, 0, 1, "case3_speed_step";
    4, 0, 1, "case4_load_step";
    5, 1, 1, "case5_lookup";
    5, 1, 0, "case5_id0"
    };

for k = 1:size(base, 1)
    srcIdx = base{k, 1};
    caseDefs(k).scenario = profiles{srcIdx, 1};
    if base{k, 4} == "case5_id0"
        caseDefs(k).label = "工况5 id=0 对比";
    elseif base{k, 4} == "case5_lookup"
        caseDefs(k).label = "工况5 lookup 对比";
    else
        caseDefs(k).label = string(profiles{srcIdx, 4});
    end
    caseDefs(k).short = char(base{k, 4});
    caseDefs(k).useLookup = base{k, 2};
    caseDefs(k).useMTPA = base{k, 3};
    caseDefs(k).eventTime = profiles{srcIdx, 5};
    caseDefs(k).speedStart = profiles{srcIdx, 6};
    caseDefs(k).speedEnd = profiles{srcIdx, 7};
    caseDefs(k).loadStart = profiles{srcIdx, 8};
    caseDefs(k).loadEnd = profiles{srcIdx, 9};
end

assignin('base', 'taskbookCaseDefs', caseDefs);
assignin('base', 'taskbookScenarioSampleTime', dt);
end

function create_lookup_tables(lookupFile)
Ld = 0.2e-3;
Lq = 0.47e-3;
psi_f = 0.062;
p = 4;
Is_max = 40;
n_pts = 401;

dL = Lq - Ld;
Is_vec = linspace(0, Is_max, n_pts);
id_table = (psi_f - sqrt(psi_f^2 + 8 * dL^2 .* Is_vec.^2)) ./ (4 * dL);
iq_table = sqrt(max(Is_vec.^2 - id_table.^2, 0));
Te_table = 1.5 * p * (psi_f .* iq_table + (Ld - Lq) .* id_table .* iq_table);

save(lookupFile, ...
    'Ld', 'Lq', 'psi_f', 'p', 'Is_max', 'Is_vec', ...
    'Te_table', 'id_table', 'iq_table');
end

function configure_table_loading(model, lookupFile)
escaped = strrep(lookupFile, '''', '''''');
loadCmd = sprintf(['tableFile = ''%s''; ' ...
    'if exist(tableFile,''file''); ' ...
    's = load(tableFile,''Is_vec'',''Te_table'',''id_table'',''iq_table''); ' ...
    'assignin(''base'',''Is_vec'',s.Is_vec); ' ...
    'assignin(''base'',''Te_table'',s.Te_table); ' ...
    'assignin(''base'',''id_table'',s.id_table); ' ...
    'assignin(''base'',''iq_table'',s.iq_table); ' ...
    'end'], escaped);
set_param(model, 'PostLoadFcn', loadCmd, 'InitFcn', loadCmd);
evalin('base', loadCmd);
end

function configure_signal_editor(model, scenarioFile)
blk = [model '/Signal Editor'];
set_param(blk, ...
    'FileName', scenarioFile, ...
    'ActiveScenario', 'Scenario1', ...
    'SampleTime', '0', ...
    'Interpolate', 'on', ...
    'OutputAfterFinalValue', 'Holding final value');
end

function configure_load_connection(model)
signalEditor = [model '/Signal Editor'];
pmsm = [model '/Permanent Magnet' newline 'Synchronous Machine'];
sePh = get_param(signalEditor, 'PortHandles');
pmsmPh = get_param(pmsm, 'PortHandles');
oldLine = get_param(pmsmPh.Inport(1), 'Line');
if oldLine ~= -1
    delete_line(oldLine);
end
add_line(model, sePh.Outport(2), pmsmPh.Inport(1), 'autorouting', 'on');
end

function configure_speed_limit(model, limitA)
speedPI = [model '/I  '];
set_param([speedPI '/Discrete-Time Integrator'], ...
    'LimitOutput', 'on', ...
    'UpperSaturationLimit', num2str(limitA), ...
    'LowerSaturationLimit', '0');
set_param([speedPI '/Saturation2'], ...
    'UpperLimit', num2str(limitA), ...
    'LowerLimit', '0');
end

function configure_mode_selection(model)
mw = get_param(model, 'ModelWorkspace');
assignin(mw, 'UseLookup_Mode', 0);
assignin(mw, 'UseMTPA_Mode', 1);

formulaBlk = find_first_block(model, 'MTPA IPMSM');
if isempty(formulaBlk)
    error('Cannot locate the formula MTPA block.');
end

formulaPh = get_param(formulaBlk, 'PortHandles');
idLine = get_param(formulaPh.Outport(1), 'Line');
iqLine = get_param(formulaPh.Outport(2), 'Line');
if idLine == -1 || iqLine == -1
    error('Formula MTPA outputs are not connected as expected.');
end

idDsts = get_param(idLine, 'DstPortHandle');
iqDsts = get_param(iqLine, 'DstPortHandle');
delete_line(idLine);
delete_line(iqLine);

speedPI = [model '/I  '];
speedPh = get_param(speedPI, 'PortHandles');

lookupId = [model '/lookup_id'];
lookupIq = [model '/lookup_iq'];
add_block('simulink/Lookup Tables/1-D Lookup Table', lookupId, ...
    'Position', [285 20 345 50], ...
    'BreakpointsForDimension1', 'Is_vec', ...
    'Table', 'id_table', ...
    'ExtrapMethod', 'Clip');
add_block('simulink/Lookup Tables/1-D Lookup Table', lookupIq, ...
    'Position', [285 100 345 130], ...
    'BreakpointsForDimension1', 'Is_vec', ...
    'Table', 'iq_table', ...
    'ExtrapMethod', 'Clip');

useLookup = [model '/UseLookup_Mode'];
useMTPA = [model '/UseMTPA_Mode'];
id0Ref = [model '/id0_ref'];
idLookupSelect = [model '/id_lookup_select'];
iqLookupSelect = [model '/iq_lookup_select'];
idModeSelect = [model '/id_mode_select'];
iqModeSelect = [model '/iq_mode_select'];

add_block('simulink/Sources/Constant', useLookup, ...
    'Position', [355 170 415 200], ...
    'Value', 'UseLookup_Mode');
add_block('simulink/Sources/Constant', useMTPA, ...
    'Position', [495 210 555 240], ...
    'Value', 'UseMTPA_Mode');
add_block('simulink/Sources/Constant', id0Ref, ...
    'Position', [500 60 550 90], ...
    'Value', '0');
add_block('simulink/Signal Routing/Switch', idLookupSelect, ...
    'Position', [430 15 470 70], ...
    'Threshold', '0.5');
add_block('simulink/Signal Routing/Switch', iqLookupSelect, ...
    'Position', [430 95 470 150], ...
    'Threshold', '0.5');
add_block('simulink/Signal Routing/Switch', idModeSelect, ...
    'Position', [575 20 615 75], ...
    'Threshold', '0.5');
add_block('simulink/Signal Routing/Switch', iqModeSelect, ...
    'Position', [575 100 615 155], ...
    'Threshold', '0.5');

idLookupPh = get_param(idLookupSelect, 'PortHandles');
iqLookupPh = get_param(iqLookupSelect, 'PortHandles');
idModePh = get_param(idModeSelect, 'PortHandles');
iqModePh = get_param(iqModeSelect, 'PortHandles');
lookupIdPh = get_param(lookupId, 'PortHandles');
lookupIqPh = get_param(lookupIq, 'PortHandles');
useLookupPh = get_param(useLookup, 'PortHandles');
useMTPAPh = get_param(useMTPA, 'PortHandles');
id0Ph = get_param(id0Ref, 'PortHandles');

add_line(model, speedPh.Outport(1), lookupIdPh.Inport(1), 'autorouting', 'on');
add_line(model, speedPh.Outport(1), lookupIqPh.Inport(1), 'autorouting', 'on');

add_line(model, formulaPh.Outport(1), idLookupPh.Inport(1), 'autorouting', 'on');
add_line(model, useLookupPh.Outport(1), idLookupPh.Inport(2), 'autorouting', 'on');
add_line(model, lookupIdPh.Outport(1), idLookupPh.Inport(3), 'autorouting', 'on');

add_line(model, formulaPh.Outport(2), iqLookupPh.Inport(1), 'autorouting', 'on');
add_line(model, useLookupPh.Outport(1), iqLookupPh.Inport(2), 'autorouting', 'on');
add_line(model, lookupIqPh.Outport(1), iqLookupPh.Inport(3), 'autorouting', 'on');

add_line(model, idLookupPh.Outport(1), idModePh.Inport(1), 'autorouting', 'on');
add_line(model, useMTPAPh.Outport(1), idModePh.Inport(2), 'autorouting', 'on');
add_line(model, id0Ph.Outport(1), idModePh.Inport(3), 'autorouting', 'on');

add_line(model, iqLookupPh.Outport(1), iqModePh.Inport(1), 'autorouting', 'on');
add_line(model, useMTPAPh.Outport(1), iqModePh.Inport(2), 'autorouting', 'on');
add_line(model, speedPh.Outport(1), iqModePh.Inport(3), 'autorouting', 'on');

for k = 1:numel(idDsts)
    add_line(model, idModePh.Outport(1), idDsts(k), 'autorouting', 'on');
end
for k = 1:numel(iqDsts)
    add_line(model, iqModePh.Outport(1), iqDsts(k), 'autorouting', 'on');
end
end

function configure_reference_logging(model)
add_toworkspace(model, [model '/id_mode_select'], 'id_ref_A', [635 25 720 55]);
add_toworkspace(model, [model '/iq_mode_select'], 'iq_ref_A', [635 105 720 135]);
end

function add_toworkspace(model, sourceBlk, varName, pos)
ph = get_param(sourceBlk, 'PortHandles');
tw = [model '/log_' varName];
if getSimulinkBlockHandle(tw) > 0
    delete_block(tw);
end
add_block('simulink/Sinks/To Workspace', tw, ...
    'VariableName', varName, ...
    'SaveFormat', 'Timeseries', ...
    'MaxDataPoints', 'inf', ...
    'Position', pos);
twPh = get_param(tw, 'PortHandles');
add_line(model, ph.Outport(1), twPh.Inport(1), 'autorouting', 'on');
end

function metrics = run_cases(root, model, caseDefs, figDir, dataDir)
metrics = repmat(struct( ...
    'case', '', ...
    'label', '', ...
    'steadySpeed', NaN, ...
    'speedError', NaN, ...
    'maxSpeed', NaN, ...
    'minSpeedAfterEvent', NaN, ...
    'speedDip', NaN, ...
    'peakCurrent', NaN, ...
    'steadyCurrent', NaN, ...
    'steadyTorque', NaN, ...
    'steadyId', NaN, ...
    'steadyIq', NaN, ...
    'overshoot', NaN, ...
    'riseTime90', NaN, ...
    'settlingTime', NaN, ...
    'recoveryTime', NaN), numel(caseDefs), 1);

mw = get_param(model, 'ModelWorkspace');

for k = 1:numel(caseDefs)
    assignin(mw, 'UseLookup_Mode', caseDefs(k).useLookup);
    assignin(mw, 'UseMTPA_Mode', caseDefs(k).useMTPA);
    set_param([model '/Signal Editor'], 'ActiveScenario', caseDefs(k).scenario);
    set_param(model, 'SimulationCommand', 'update');
    out = sim(model, 'StopTime', '1');
    raw = extract_case_data(root, out, caseDefs(k));
    save(fullfile(dataDir, [caseDefs(k).short '.mat']), 'raw');
    metrics(k) = summarize_case(raw, caseDefs(k));
    plot_case(raw, caseDefs(k), fullfile(figDir, [caseDefs(k).short '_waveforms.png']));
end

plot_compare_case(dataDir, figDir);
end

function raw = extract_case_data(root, out, caseDef)
scenarioStruct = load(fullfile(root, 'scenario.mat'), caseDef.scenario);
scenario = scenarioStruct.(caseDef.scenario);

raw = struct();
raw.n_ref = get_ts_from_dataset(scenario, 'n_ref');
raw.Tm = get_ts_from_dataset(scenario, 'Tm');
raw.n_rpm = get_logged(out.logsout, 'n_rpm');
raw.id = get_logged(out.logsout, 'id_official');
raw.iq = get_logged(out.logsout, 'iq_official');
raw.Is_cmd = get_logged(out.logsout, 'Is_cmd');
raw.Te = get_logged(out.logsout, 'Te');
raw.ud_star = get_logged(out.logsout, 'ud_star');
raw.uq_star = get_logged(out.logsout, 'uq_star');
raw.id_ref = out.id_ref_A;
raw.iq_ref = out.iq_ref_A;

scope = out.ScopeData4;
raw.iabc_time = scope(:, 1);
raw.iabc = scope(:, 2:4);
end

function ts = get_logged(ds, name)
ts = ds.get(name).Values;
end

function ts = get_ts_from_dataset(ds, name)
element = ds.getElement(name);
if isa(element, 'timeseries')
    ts = element;
else
    ts = element.Values;
end
end

function m = summarize_case(raw, caseDef)
t = raw.n_rpm.Time(:);
nRef = interp1(raw.n_ref.Time(:), raw.n_ref.Data(:), t, 'linear', 'extrap');
n = raw.n_rpm.Data(:);
te = raw.Te.Data(:);
id = raw.id.Data(:);
iq = raw.iq.Data(:);
is = hypot(id, iq);

tail = t >= 0.9;
m.case = caseDef.short;
m.label = char(caseDef.label);
m.steadySpeed = mean(n(tail), 'omitnan');
m.speedError = mean(nRef(tail) - n(tail), 'omitnan');
m.maxSpeed = max(n, [], 'omitnan');
m.minSpeedAfterEvent = min(n(t >= max(caseDef.eventTime, 0.0)), [], 'omitnan');
m.speedDip = max(n(t >= max(caseDef.eventTime - 0.05, 0.0) & t <= max(caseDef.eventTime, 0.05)), [], 'omitnan') ...
    - min(n(t >= max(caseDef.eventTime, 0.0) & t <= min(caseDef.eventTime + 0.3, t(end))), [], 'omitnan');
m.peakCurrent = max(is, [], 'omitnan');
m.steadyCurrent = mean(is(tail), 'omitnan');
m.steadyTorque = mean(te(tail), 'omitnan');
m.steadyId = mean(id(tail), 'omitnan');
m.steadyIq = mean(iq(tail), 'omitnan');
m.overshoot = max(n, [], 'omitnan') - caseDef.speedEnd;
m.riseTime90 = compute_rise_time(t, n, caseDef);
m.settlingTime = compute_settling_time(t, n, caseDef);
m.recoveryTime = compute_recovery_time(t, n, caseDef);
end

function riseTime = compute_rise_time(t, n, caseDef)
riseTime = NaN;
delta = caseDef.speedEnd - caseDef.speedStart;
if abs(delta) < 1e-9
    return;
end
target90 = caseDef.speedStart + 0.9 * delta;
mask = t >= caseDef.eventTime;
idx = find(mask & n >= target90, 1, 'first');
if ~isempty(idx)
    riseTime = t(idx) - caseDef.eventTime;
end
end

function settlingTime = compute_settling_time(t, n, caseDef)
settlingTime = NaN;
delta = caseDef.speedEnd - caseDef.speedStart;
if abs(delta) < 1e-9
    return;
end
band = max(0.02 * abs(delta), 5.0);
mask = t >= caseDef.eventTime;
idxCandidates = find(mask);
for k = 1:numel(idxCandidates)
    idx = idxCandidates(k);
    if all(abs(n(idx:end) - caseDef.speedEnd) <= band)
        settlingTime = t(idx) - caseDef.eventTime;
        return;
    end
end
end

function recoveryTime = compute_recovery_time(t, n, caseDef)
recoveryTime = NaN;
if abs(caseDef.loadEnd - caseDef.loadStart) < 1e-9
    return;
end
band = max(0.01 * max(caseDef.speedEnd, 1), 5.0);
mask = t >= caseDef.eventTime;
idxCandidates = find(mask);
for k = 1:numel(idxCandidates)
    idx = idxCandidates(k);
    if all(abs(n(idx:end) - caseDef.speedEnd) <= band)
        recoveryTime = t(idx) - caseDef.eventTime;
        return;
    end
end
end

function plot_case(raw, caseDef, outFile)
t = raw.n_rpm.Time(:);
nRef = interp1(raw.n_ref.Time(:), raw.n_ref.Data(:), t, 'linear', 'extrap');
loadNm = interp1(raw.Tm.Time(:), raw.Tm.Data(:), t, 'linear', 'extrap');
n = raw.n_rpm.Data(:);
te = raw.Te.Data(:);
id = raw.id.Data(:);
iq = raw.iq.Data(:);
idRef = interp1(raw.id_ref.Time(:), raw.id_ref.Data(:), t, 'linear', 'extrap');
iqRef = interp1(raw.iq_ref.Time(:), raw.iq_ref.Data(:), t, 'linear', 'extrap');
is = hypot(id, iq);
ud = raw.ud_star.Data(:);
uq = raw.uq_star.Data(:);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1320 960]);
tiledlayout(3, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(t, nRef, 'k--', 'LineWidth', 1.1);
hold on;
plot(t, n, 'b', 'LineWidth', 1.2);
grid on;
title([char(caseDef.label) ' 转速响应']);
xlabel('t / s');
ylabel('n / rpm');
legend('n*', 'n', 'Location', 'best');

nexttile;
plot(t, te, 'r', 'LineWidth', 1.2);
hold on;
plot(t, loadNm, 'k--', 'LineWidth', 1.1);
grid on;
title('电磁转矩与负载转矩');
xlabel('t / s');
ylabel('T / N·m');
legend('Te', 'TL', 'Location', 'best');

nexttile;
plot(t, id, 'b', 'LineWidth', 1.1);
hold on;
plot(t, iq, 'r', 'LineWidth', 1.1);
plot(t, idRef, 'b--', 'LineWidth', 0.9);
plot(t, iqRef, 'r--', 'LineWidth', 0.9);
grid on;
title('dq 轴电流及给定');
xlabel('t / s');
ylabel('i / A');
legend('id', 'iq', 'id*', 'iq*', 'Location', 'best');

nexttile;
plot(t, is, 'm', 'LineWidth', 1.2);
grid on;
title('电流幅值');
xlabel('t / s');
ylabel('Is / A');

nexttile;
plot(t, ud, 'b', 'LineWidth', 1.1);
hold on;
plot(t, uq, 'r', 'LineWidth', 1.1);
grid on;
title('dq 轴电压指令');
xlabel('t / s');
ylabel('u / V');
legend('ud*', 'uq*', 'Location', 'best');

nexttile;
plot(raw.iabc_time, raw.iabc(:, 1), 'r', 'LineWidth', 0.9);
hold on;
plot(raw.iabc_time, raw.iabc(:, 2), 'g', 'LineWidth', 0.9);
plot(raw.iabc_time, raw.iabc(:, 3), 'b', 'LineWidth', 0.9);
grid on;
title('三相电流');
xlabel('t / s');
ylabel('iabc / A');
legend('ia', 'ib', 'ic', 'Location', 'best');

exportgraphics(fig, outFile, 'Resolution', 180);
close(fig);
end

function plot_compare_case(dataDir, figDir)
lookupRaw = load(fullfile(dataDir, 'case5_lookup.mat')).raw;
id0Raw = load(fullfile(dataDir, 'case5_id0.mat')).raw;

t = lookupRaw.n_rpm.Time(:);
nLookup = lookupRaw.n_rpm.Data(:);
nId0 = interp1(id0Raw.n_rpm.Time(:), id0Raw.n_rpm.Data(:), t, 'linear', 'extrap');
teLookup = lookupRaw.Te.Data(:);
teId0 = interp1(id0Raw.Te.Time(:), id0Raw.Te.Data(:), t, 'linear', 'extrap');
idLookup = lookupRaw.id.Data(:);
iqLookup = lookupRaw.iq.Data(:);
idId0 = interp1(id0Raw.id.Time(:), id0Raw.id.Data(:), t, 'linear', 'extrap');
iqId0 = interp1(id0Raw.iq.Time(:), id0Raw.iq.Data(:), t, 'linear', 'extrap');
isLookup = hypot(idLookup, iqLookup);
isId0 = hypot(idId0, iqId0);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1250 840]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(t, nLookup, 'b', 'LineWidth', 1.2);
hold on;
plot(t, nId0, 'r--', 'LineWidth', 1.2);
grid on;
title('工况5 转速对比');
xlabel('t / s');
ylabel('n / rpm');
legend('lookup', 'id=0', 'Location', 'best');

nexttile;
plot(t, teLookup, 'b', 'LineWidth', 1.2);
hold on;
plot(t, teId0, 'r--', 'LineWidth', 1.2);
grid on;
title('工况5 电磁转矩对比');
xlabel('t / s');
ylabel('Te / N·m');
legend('lookup', 'id=0', 'Location', 'best');

nexttile;
plot(t, isLookup, 'b', 'LineWidth', 1.2);
hold on;
plot(t, isId0, 'r--', 'LineWidth', 1.2);
grid on;
title('工况5 电流幅值对比');
xlabel('t / s');
ylabel('Is / A');
legend('lookup', 'id=0', 'Location', 'best');

nexttile;
plot(t, idLookup, 'b', 'LineWidth', 1.1);
hold on;
plot(t, iqLookup, 'c', 'LineWidth', 1.1);
plot(t, idId0, 'r--', 'LineWidth', 1.1);
plot(t, iqId0, 'm--', 'LineWidth', 1.1);
grid on;
title('工况5 dq 电流对比');
xlabel('t / s');
ylabel('i / A');
legend('id lookup', 'iq lookup', 'id id=0', 'iq id=0', 'Location', 'best');

exportgraphics(fig, fullfile(figDir, 'case5_lookup_vs_id0_compare.png'), 'Resolution', 180);
close(fig);
end

function export_model_shots(model, simDir)
shots = {
    model, '00_top_level';
    [model '/Signal Editor'], '01_signal_editor';
    [model '/MTPA IPMSM(缁欏畾Is锛屽埄鐢ㄥ叕寮忔眰idq)'], '02_mtpa_formula';
    [model '/lookup_id'], '03_lookup_id';
    [model '/lookup_iq'], '04_lookup_iq';
    };

for k = 1:size(shots, 1)
    sys = shots{k, 1};
    name = shots{k, 2};
    try
        open_system(sys);
        try
            set_param(sys, 'ZoomFactor', 'FitSystem');
        catch
        end
        drawnow;
        print(['-s' sys], '-dpng', '-r180', fullfile(simDir, [name '.png']));
        if ~strcmp(sys, model)
            close_system(sys);
        end
    catch
    end
end
end

function blk = find_first_block(model, nameStart)
blk = '';
blks = find_system(model, 'SearchDepth', 1, 'Type', 'Block');
for k = 1:numel(blks)
    name = get_param(blks{k}, 'Name');
    if startsWith(name, nameStart)
        blk = blks{k};
        return;
    end
end
end
