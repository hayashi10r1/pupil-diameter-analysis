function outputDirectory = analyze_pupil_wavelets(sessionFiles)
% ANALYZE_PUPIL_WAVELETS Run CWT on each complete recording session.
% 各セッション全体の瞳孔時系列に連続ウェーブレット変換（CWT）を行います。
%
% Usage:
%   analyze_pupil_wavelets
%   analyze_pupil_wavelets({'C:\path\to\session1.mat', ...
%       'C:\path\to\session2.mat', 'C:\path\to\session3.mat'})
%
% Requires Wavelet Toolbox for cwt().

analysis = defaultAnalysisConfig();
assert(exist('cwt', 'file') ~= 0, ...
    ['Wavelet Toolbox is required. The MATLAB function cwt() was not ', ...
     'found on the current MATLAB path.']);

if nargin < 1 || isempty(sessionFiles)
    sessionFiles = selectThreeSessionFiles();
    if isempty(sessionFiles)
        outputDirectory = '';
        return;
    end
end

sessionFiles = normalizeFileList(sessionFiles);
assert(numel(sessionFiles) == analysis.sessionCount, ...
    'Select exactly %d session MAT files for one participant.', analysis.sessionCount);
assert(all(cellfun(@isfile, sessionFiles)), 'One or more session files were not found.');

[firstFolder, firstName] = fileparts(sessionFiles{1});
outputDirectory = fullfile(firstFolder, sprintf('%s_full_session_wavelets_%s', ...
    firstName, datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(outputDirectory);

sessionResults = cell(analysis.sessionCount, 1);
for iSession = 1:analysis.sessionCount
    loadedData = load(sessionFiles{iSession}, 'gazeData', 'trialLog', 'metadata', 'cfg');
    validateExperimentData(loadedData, sessionFiles{iSession});
    sessionResults{iSession} = analyzeFullSession(loadedData, iSession, analysis);
    saveFullSessionScalogram(sessionResults{iSession}, outputDirectory, analysis);
end

waveletResults = struct( ...
    'analysisSettings', analysis, ...
    'sessionFiles', {sessionFiles}, ...
    'sessionResults', {sessionResults});
save(fullfile(outputDirectory, 'wavelet_results.mat'), 'waveletResults', '-v7.3');

fprintf('Saved whole-session CWT results for %d sessions to:\n%s\n', ...
    analysis.sessionCount, outputDirectory);
end

function analysis = defaultAnalysisConfig()
% Change these values when a different frequency band is required.
analysis.sessionCount = 3;
analysis.frequencyLimitsHz = [0.1 10.0];
analysis.warnMissingFraction = 0.20;
analysis.showFigures = true;
end

function result = analyzeFullSession(loadedData, sessionNumber, analysis)
[timestampsUS, pupilMM] = bilateralPupilSeries(loadedData.gazeData);
sampleRateHz = getSampleRateHz(loadedData);
[timeSeconds, resampledPupil, missingFraction, firstTimestampUS] = ...
    resampleFullRecording(timestampsUS, pupilMM, sampleRateHz);

if missingFraction > analysis.warnMissingFraction
    warning('AnalyzePupilWavelets:HighMissingFraction', ...
        ['Session %d has %.1f%% missing pupil samples before interpolation. ', ...
         'Interpret its CWT result with caution.'], ...
        sessionNumber, missingFraction * 100);
end

% Use the interpolated pupil diameter in mm without z-scoring.
% Z得点化せず、補間後の瞳孔径（mm）をそのままCWTへ渡します。
[coefficients, frequencyHz] = cwt(resampledPupil, sampleRateHz, 'amor', ...
    'FrequencyLimits', analysis.frequencyLimitsHz);
stimulusMarkers = getStimulusMarkers(loadedData, firstTimestampUS);

result = struct( ...
    'session', sessionNumber, ...
    'timeSeconds', timeSeconds, ...
    'frequencyHz', frequencyHz(:), ...
    'frequencyLimitsHz', analysis.frequencyLimitsHz, ...
    'power', abs(coefficients) .^ 2, ...
    'powerUnit', 'mm^2 (approximately)', ...
    'missingFraction', missingFraction, ...
    'sampleRateHz', sampleRateHz, ...
    'stimulusOnsetMinutes', reshape([stimulusMarkers.onsetMinutes], [], 1), ...
    'stimulusMarkers', stimulusMarkers);
end

function saveFullSessionScalogram(result, outputDirectory, analysis)
if analysis.showFigures
    visibility = 'on';
else
    visibility = 'off';
end
figureHandle = figure('Color', 'w', 'Visible', visibility, ...
    'Position', [100 100 1600 700]);
imagesc(result.timeSeconds ./ 60, result.frequencyHz, result.power);
axis xy;
set(gca, 'YScale', 'log');
ylim(result.frequencyLimitsHz);
hold on;

% Solid white lines are stimulus onsets; dashed lines are offsets.
% 白い実線は刺激オン、白い破線は刺激オフです。CWT自体は全区間に対して行います。
for marker = result.stimulusMarkers
    xline(marker.onsetMinutes, '-', 'Color', 'w', 'LineWidth', 1.2);
    if isfinite(marker.offsetMinutes)
        xline(marker.offsetMinutes, '--', 'Color', 'w', 'LineWidth', 0.9);
    end
end

xlabel('Time (m)');
ylabel('Frequency (Hz)');
title(sprintf(['Whole-session wavelet power: Session %d ', ...
    '(solid=stimulus on, dashed=stimulus off)'], ...
    result.session));
colorbar;
colormap(turbo);

imageFile = fullfile(outputDirectory, ...
    sprintf('session_%02d_full_recording.png', result.session));
exportgraphics(figureHandle, imageFile, 'Resolution', 200);
figureFile = fullfile(outputDirectory, ...
    sprintf('session_%02d_full_recording.fig', result.session));
savefig(figureHandle, figureFile);
if ~analysis.showFigures
    close(figureHandle);
end
end

function [timeSeconds, resampledPupil, missingFraction, firstTimestampUS] = ...
        resampleFullRecording(timestampsUS, pupilMM, sampleRateHz)
validTime = isfinite(timestampsUS);
assert(any(validTime), 'No valid timestamps were found.');
firstTimestampUS = timestampsUS(find(validTime, 1, 'first'));
lastTimestampUS = timestampsUS(find(validTime, 1, 'last'));
rawTimeSeconds = (timestampsUS - firstTimestampUS) ./ 1e6;
timeSeconds = (0 : 1 / sampleRateHz : ...
    (lastTimestampUS - firstTimestampUS) ./ 1e6)';

validPupil = validTime & isfinite(pupilMM);
assert(nnz(validPupil) >= 2, 'Not enough valid pupil samples were found.');
[sourceTime, uniqueIndex] = unique(rawTimeSeconds(validPupil));
sourcePupil = pupilMM(validPupil);
sourcePupil = sourcePupil(uniqueIndex);
resampledPupil = interp1(sourceTime, sourcePupil, timeSeconds, 'pchip', NaN);
missingFraction = mean(isnan(resampledPupil));

% CWT cannot accept NaN. Missing samples are interpolated after the
% missing fraction is stored and reported to the user.
% CWTはNaNを受け取れないため、欠損率を記録した後に補間します。
resampledPupil = fillmissing(resampledPupil, 'linear', 'EndValues', 'nearest');
end

function stimulusMarkers = getStimulusMarkers(loadedData, firstTimestampUS)
stimulusMarkers = struct('onsetMinutes', {}, 'offsetMinutes', {}, 'colorRGB', {});
if ~isfield(loadedData, 'trialLog') || isempty(loadedData.trialLog)
    return;
end

for iTrial = 1:numel(loadedData.trialLog)
    trial = loadedData.trialLog(iTrial);
    onsetMinutes = NaN;
    offsetMinutes = NaN;
    if isfield(trial, 'tobiiSystemOnsetUS') && isfinite(trial.tobiiSystemOnsetUS)
        onsetMinutes = (double(trial.tobiiSystemOnsetUS) - firstTimestampUS) ./ (60 * 1e6);
        if isfield(trial, 'tobiiSystemOffsetUS') && isfinite(trial.tobiiSystemOffsetUS)
            offsetMinutes = (double(trial.tobiiSystemOffsetUS) - firstTimestampUS) ./ (60 * 1e6);
        end
    elseif isfield(trial, 'stimulusOnsetPTB') && isfield(loadedData, 'metadata') && ...
            isfield(loadedData.metadata, 'recordingStartPTB') && ...
            isfinite(loadedData.metadata.recordingStartPTB)
        onsetMinutes = (trial.stimulusOnsetPTB - loadedData.metadata.recordingStartPTB) ./ 60;
        if isfield(trial, 'stimulusOffsetPTB') && isfinite(trial.stimulusOffsetPTB)
            offsetMinutes = (trial.stimulusOffsetPTB - loadedData.metadata.recordingStartPTB) ./ 60;
        end
    end
    if isfinite(onsetMinutes)
        stimulusMarkers(end + 1) = struct( ...
            'onsetMinutes', onsetMinutes, ...
            'offsetMinutes', offsetMinutes, ...
            'colorRGB', getTrialColorRGB(trial)); %#ok<AGROW>
    end
end
end

function colorRGB = getTrialColorRGB(trial)
if isfield(trial, 'colorRGB')
    colorRGB = double(trial.colorRGB);
elseif isfield(trial, 'colourRGB')
    % Compatibility for files saved before colorRGB was renamed.
    colorRGB = double(trial.colourRGB);
else
    error('AnalyzePupilWavelets:ColorNotFound', ...
        'trialLog does not contain colorRGB.');
end
end

function [timestampsUS, pupilMM] = bilateralPupilSeries(gazeData)
required = {'systemTimeStampUS', 'leftPupilDiameterMM', 'rightPupilDiameterMM'};
assert(isstruct(gazeData) && all(isfield(gazeData, required)), ...
    'gazeData does not contain numeric pupil time-series fields. Use production-mode data.');

timestampsUS = double(gazeData.systemTimeStampUS(:));
leftPupilMM = double(gazeData.leftPupilDiameterMM(:));
rightPupilMM = double(gazeData.rightPupilDiameterMM(:));
assert(numel(timestampsUS) == numel(leftPupilMM) && ...
    numel(timestampsUS) == numel(rightPupilMM), ...
    'Pupil and timestamp arrays must have the same length.');

% Use the mean when both eyes are valid; otherwise use the valid eye.
% 両眼が有効なら平均値、片眼のみ有効ならその片眼の値を使います。
pupilMM = leftPupilMM;
bothValid = isfinite(leftPupilMM) & isfinite(rightPupilMM);
rightOnly = ~isfinite(leftPupilMM) & isfinite(rightPupilMM);
pupilMM(bothValid) = mean([leftPupilMM(bothValid), rightPupilMM(bothValid)], 2);
pupilMM(rightOnly) = rightPupilMM(rightOnly);
end

function sampleRateHz = getSampleRateHz(loadedData)
if isfield(loadedData, 'cfg') && isfield(loadedData.cfg, 'samplingFrequencyHz')
    sampleRateHz = double(loadedData.cfg.samplingFrequencyHz);
else
    sampleRateHz = 60;
end
assert(isfinite(sampleRateHz) && sampleRateHz > 2, 'Invalid sampling frequency.');
end

function validateExperimentData(loadedData, fileName)
assert(isfield(loadedData, 'gazeData'), ...
    'The file does not contain gazeData: %s', fileName);
end

function sessionFiles = selectThreeSessionFiles()
[fileNames, folderName] = uigetfile({'*.mat', 'MATLAB data files (*.mat)'}, ...
    '同じ参加者の3セッション分のMATファイルを選択', pwd, 'MultiSelect', 'on');
if isequal(fileNames, 0)
    sessionFiles = {};
    return;
end
if ischar(fileNames)
    fileNames = {fileNames};
end
sessionFiles = cellfun(@(name) fullfile(folderName, name), fileNames, ...
    'UniformOutput', false);
end

function sessionFiles = normalizeFileList(sessionFiles)
if ischar(sessionFiles)
    sessionFiles = {sessionFiles};
elseif isstring(sessionFiles)
    sessionFiles = cellstr(sessionFiles);
end
assert(iscell(sessionFiles), 'sessionFiles must be a cell array of MAT-file paths.');
assert(all(cellfun(@(fileName) ischar(fileName) || isstring(fileName), sessionFiles)), ...
    'Every session file path must be text.');
sessionFiles = cellfun(@char, sessionFiles, 'UniformOutput', false);
sessionFiles = reshape(sessionFiles, 1, []);
end
