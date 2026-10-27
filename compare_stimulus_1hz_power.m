function outputDirectory = compare_stimulus_1hz_power(waveletResultsFile)
% COMPARE_STIMULUS_1HZ_POWER Compare 1-Hz-band power across stimuli.
% 全セッションCWTの結果から、各刺激提示後5〜35秒・0.8〜1.2 Hzの
% 平均パワーを求め、RGB刺激ごとに比較します。
%
% Usage:
%   compare_stimulus_1hz_power
%   compare_stimulus_1hz_power('C:\path\to\wavelet_results.mat')

settings = defaultComparisonSettings();
luminanceLUT = loadLuminanceLUT();

if nargin < 1 || isempty(waveletResultsFile)
    [fileName, folderName] = uigetfile({'wavelet_results.mat', ...
        'Wavelet results (wavelet_results.mat)'}, ...
        'Select wavelet_results.mat', pwd);
    if isequal(fileName, 0)
        outputDirectory = '';
        return;
    end
    waveletResultsFile = fullfile(folderName, fileName);
end
assert(isfile(waveletResultsFile), ...
    'Wavelet results file not found: %s', waveletResultsFile);

loadedResults = load(waveletResultsFile, 'waveletResults');
assert(isfield(loadedResults, 'waveletResults'), ...
    'The selected file does not contain waveletResults.');
waveletResults = loadedResults.waveletResults;
assert(isfield(waveletResults, 'sessionResults') && ...
    isfield(waveletResults, 'sessionFiles'), ...
    ['This file must be created by the full-session version of ', ...
     'analyze_pupil_wavelets.m.']);

[resultsFolder, ~] = fileparts(waveletResultsFile);
outputDirectory = fullfile(resultsFolder, 'stimulus_1hz_power_comparison');
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

sessionTrialTables = cell(numel(waveletResults.sessionResults), 1);
for iSession = 1:numel(waveletResults.sessionResults)
    sessionResult = waveletResults.sessionResults{iSession};
    sessionFile = waveletResults.sessionFiles{iSession};
    sessionTrialTable = extractSessionPower(sessionResult, sessionFile, ...
        iSession, settings, luminanceLUT);
    sessionTrialTables{iSession} = sessionTrialTable;
end
trialTable = vertcat(sessionTrialTables{:});
assert(~isempty(trialTable), 'No valid stimulus windows were found.');

summaryTable = summarizeByColor(trialTable);
writetable(trialTable, fullfile(outputDirectory, 'stimulus_1hz_power_by_trial.csv'));
writetable(summaryTable, fullfile(outputDirectory, 'stimulus_1hz_power_by_color.csv'));
saveComparisonFigure(trialTable, summaryTable, settings, outputDirectory);

save(fullfile(outputDirectory, 'stimulus_1hz_power_results.mat'), ...
    'settings', 'trialTable', 'summaryTable');
disp(summaryTable);
fprintf('Saved 1-Hz power comparison to:\n%s\n', outputDirectory);
end

function settings = defaultComparisonSettings()
settings.timeWindowSeconds = [5 35];
settings.frequencyBandHz = [0.8 1.2];
settings.showFigure = true;
end

function sessionTrialTable = extractSessionPower(sessionResult, sessionFile, sessionNumber, settings, luminanceLUT)
requiredFields = {'timeSeconds', 'frequencyHz', 'power', 'stimulusOnsetMinutes'};
assert(all(isfield(sessionResult, requiredFields)), ...
    'Session %d does not contain the required full-session CWT results.', sessionNumber);

sessionData = load(sessionFile, 'trialLog');
assert(isfield(sessionData, 'trialLog') && ~isempty(sessionData.trialLog), ...
    'Session file has no trialLog: %s', sessionFile);
assert(numel(sessionData.trialLog) == numel(sessionResult.stimulusOnsetMinutes), ...
    ['The number of trials and stimulus-onset markers differs in session %d. ', ...
     'Re-run analyze_pupil_wavelets.m with the current experiment data.'], sessionNumber);

timeSeconds = double(sessionResult.timeSeconds(:));
frequencyHz = double(sessionResult.frequencyHz(:));
power = double(sessionResult.power);
assert(size(power, 1) == numel(frequencyHz) && size(power, 2) == numel(timeSeconds), ...
    'CWT power dimensions do not match its frequency and time vectors.');
frequencyMask = frequencyHz >= settings.frequencyBandHz(1) & ...
    frequencyHz <= settings.frequencyBandHz(2);
assert(any(frequencyMask), 'No CWT frequencies fall within the requested 0.8-1.2 Hz band.');

trialNumber = zeros(numel(sessionData.trialLog), 1);
redDigit = zeros(numel(sessionData.trialLog), 1);
greenDigit = zeros(numel(sessionData.trialLog), 1);
blueDigit = zeros(numel(sessionData.trialLog), 1);
meanPower = nan(numel(sessionData.trialLog), 1);
usedSampleCount = zeros(numel(sessionData.trialLog), 1);
luminanceCdM2 = nan(numel(sessionData.trialLog), 1);

for iTrial = 1:numel(sessionData.trialLog)
    trial = sessionData.trialLog(iTrial);
    colorRGB = getTrialColorRGB(trial);
    onsetSeconds = double(sessionResult.stimulusOnsetMinutes(iTrial)) * 60;
    relativeTimeSeconds = timeSeconds - onsetSeconds;
    timeMask = relativeTimeSeconds >= settings.timeWindowSeconds(1) & ...
        relativeTimeSeconds <= settings.timeWindowSeconds(2);
    assert(any(timeMask), ...
        'No CWT samples in the requested time window for session %d, trial %d.', ...
        sessionNumber, iTrial);

    powerWindow = power(frequencyMask, timeMask);
    meanPower(iTrial) = mean(powerWindow, 'all', 'omitnan');
    usedSampleCount(iTrial) = nnz(isfinite(powerWindow));
    trialNumber(iTrial) = getTrialNumber(trial, iTrial);
    redDigit(iTrial) = colorRGB(1);
    greenDigit(iTrial) = colorRGB(2);
    blueDigit(iTrial) = colorRGB(3);
    luminanceCdM2(iTrial) = lookupLuminance(colorRGB, luminanceLUT);
end

sessionColumn = repmat(sessionNumber, numel(trialNumber), 1);
sessionTrialTable = table(sessionColumn, trialNumber, redDigit, greenDigit, ...
    blueDigit, luminanceCdM2, meanPower, usedSampleCount, ...
    'VariableNames', {'Session', 'Trial', 'RedDigit', 'GreenDigit', ...
    'BlueDigit', 'Luminance_cd_m2', 'MeanPower_0p8to1p2Hz_5to35s', ...
    'UsedPowerSamples'});
end

function summaryTable = summarizeByColor(trialTable)
rgbLabel = compose('RGB [%d %d %d]', trialTable.RedDigit, ...
    trialTable.GreenDigit, trialTable.BlueDigit);
[uniqueLabels, ~, groupIndex] = unique(rgbLabel, 'stable');
nColors = numel(uniqueLabels);
redDigit = zeros(nColors, 1);
greenDigit = zeros(nColors, 1);
blueDigit = zeros(nColors, 1);
nObservations = zeros(nColors, 1);
meanPower = nan(nColors, 1);
standardDeviation = nan(nColors, 1);
standardError = nan(nColors, 1);
luminanceCdM2 = nan(nColors, 1);

for iColor = 1:nColors
    rows = groupIndex == iColor;
    values = trialTable.MeanPower_0p8to1p2Hz_5to35s(rows);
    values = values(isfinite(values));
    redDigit(iColor) = trialTable.RedDigit(find(rows, 1, 'first'));
    greenDigit(iColor) = trialTable.GreenDigit(find(rows, 1, 'first'));
    blueDigit(iColor) = trialTable.BlueDigit(find(rows, 1, 'first'));
    luminanceValues = trialTable.Luminance_cd_m2(rows);
    luminanceCdM2(iColor) = mean(luminanceValues, 'omitnan');
    nObservations(iColor) = numel(values);
    meanPower(iColor) = mean(values, 'omitnan');
    standardDeviation(iColor) = std(values, 'omitnan');
    standardError(iColor) = standardDeviation(iColor) ./ sqrt(nObservations(iColor));
end

summaryTable = table(redDigit, greenDigit, blueDigit, luminanceCdM2, nObservations, ...
    meanPower, standardDeviation, standardError, ...
    'VariableNames', {'RedDigit', 'GreenDigit', 'BlueDigit', ...
    'Luminance_cd_m2', 'N', 'MeanPower_0p8to1p2Hz_5to35s', 'SD', 'SEM'});
summaryTable = sortColors(summaryTable);
end

function sortedTable = sortColors(summaryTable)
% Order primary colors by hue, then dark-to-light within each color.
% 赤、緑、青、グレースケールの順に並べ、各色内では暗い順にします。
rgb = [summaryTable.RedDigit, summaryTable.GreenDigit, summaryTable.BlueDigit];
colorGroup = 5 * ones(height(summaryTable), 1);
colorGroup(rgb(:, 1) > 0 & rgb(:, 2) == 0 & rgb(:, 3) == 0) = 1;
colorGroup(rgb(:, 1) == 0 & rgb(:, 2) > 0 & rgb(:, 3) == 0) = 2;
colorGroup(rgb(:, 1) == 0 & rgb(:, 2) == 0 & rgb(:, 3) > 0) = 3;
colorGroup(rgb(:, 1) == rgb(:, 2) & rgb(:, 2) == rgb(:, 3)) = 4;
intensity = max(rgb, [], 2);
[~, order] = sortrows([colorGroup, intensity, rgb], [1 2 3 4 5]);
sortedTable = summaryTable(order, :);
end

function saveComparisonFigure(trialTable, summaryTable, settings, outputDirectory)
if settings.showFigure
    visibility = 'on';
else
    visibility = 'off';
end
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Position', [100 100 1800 750]);
nColors = height(summaryTable);
x = 1:nColors;
barHandle = bar(x, summaryTable.MeanPower_0p8to1p2Hz_5to35s, ...
    'FaceColor', 'flat', 'EdgeColor', [0.1 0.1 0.1], 'LineWidth', 1.2);
barHandle.CData = [summaryTable.RedDigit, summaryTable.GreenDigit, ...
    summaryTable.BlueDigit] ./ 255;
hold on;

colorLabels = compose('%.1f cd/m^2', summaryTable.Luminance_cd_m2);
for iColor = 1:nColors
    rows = trialTable.RedDigit == summaryTable.RedDigit(iColor) & ...
        trialTable.GreenDigit == summaryTable.GreenDigit(iColor) & ...
        trialTable.BlueDigit == summaryTable.BlueDigit(iColor);
    values = trialTable.MeanPower_0p8to1p2Hz_5to35s(rows);
    if numel(values) == 1
        offsets = 0;
    else
        offsets = linspace(-0.14, 0.14, numel(values));
    end
    scatter(iColor + offsets, values, 32, 'k', 'filled', ...
        'MarkerFaceAlpha', 0.65);
end

grid on;
xlim([0.4 nColors + 0.6]);
xticks(x);
xticklabels(colorLabels);
xtickangle(45);
xlabel('Stimulus luminance (cd/m^2)');
ylabel('Mean CWT power (0.8-1.2 Hz, 5-35 s)');
title('Comparison of 1-Hz-band pupil power by stimulus');

pngFile = fullfile(outputDirectory, 'stimulus_1hz_power_comparison.png');
figFile = fullfile(outputDirectory, 'stimulus_1hz_power_comparison.fig');
exportgraphics(figureHandle, pngFile, 'Resolution', 200);
savefig(figureHandle, figFile);
if ~settings.showFigure
    close(figureHandle);
end
end

function colorRGB = getTrialColorRGB(trial)
if isfield(trial, 'colorRGB')
    colorRGB = double(trial.colorRGB);
elseif isfield(trial, 'colourRGB')
    % Compatibility for files saved before colorRGB was renamed.
    colorRGB = double(trial.colourRGB);
else
    error('CompareStimulus1HzPower:ColorNotFound', ...
        'trialLog does not contain colorRGB.');
end
end

function trialNumber = getTrialNumber(trial, fallbackNumber)
if isfield(trial, 'trial') && isfinite(trial.trial)
    trialNumber = double(trial.trial);
else
    trialNumber = fallbackNumber;
end
end

function luminanceLUT = loadLuminanceLUT()
% Load the Specbos RGB-to-luminance lookup table stored with this project.
projectFolder = fileparts(mfilename('fullpath'));
calibrationFiles = dir(fullfile(projectFolder, 'SpecbosData-*.mat'));
assert(numel(calibrationFiles) == 1, ...
    ['Place exactly one SpecbosData-*.mat calibration file beside ', ...
     'compare_stimulus_1hz_power.m.']);
calibrationFile = fullfile(calibrationFiles.folder, calibrationFiles.name);
calibrationData = load(calibrationFile, 'iRGB', 'Luminance');
assert(isfield(calibrationData, 'iRGB') && isfield(calibrationData, 'Luminance'), ...
    'The Specbos calibration file must contain iRGB and Luminance.');
luminanceLUT = struct( ...
    'RGB', double(calibrationData.iRGB), ...
    'LuminanceCdM2', double(calibrationData.Luminance(:)));
assert(size(luminanceLUT.RGB, 2) == 3 && ...
    size(luminanceLUT.RGB, 1) == numel(luminanceLUT.LuminanceCdM2), ...
    'Invalid iRGB or Luminance dimensions in the Specbos calibration file.');
end

function luminanceCdM2 = lookupLuminance(colorRGB, luminanceLUT)
matches = all(luminanceLUT.RGB == colorRGB, 2);
if any(matches)
    luminanceCdM2 = mean(luminanceLUT.LuminanceCdM2(matches), 'omitnan');
else
    luminanceCdM2 = NaN;
    warning('CompareStimulus1HzPower:RGBNotInLUT', ...
        'No Specbos LUT entry for RGB [%d %d %d].', colorRGB);
end
end
