function outputDirectory = plot_pupil_windows_by_color(dataFile)
% PLOT_PUPIL_WINDOWS_BY_COLOR Save one 70-second pupil plot for each color.
%
% Each window spans 30 seconds of dark adaptation before stimulus onset and
% 40 seconds of color stimulation after onset. Pupil size is the mean of
% the valid left- and right-eye diameter samples.
%
% Usage:
%   plot_pupil_windows_by_color
%   plot_pupil_windows_by_color('C:\path\to\recording.mat')

darkAdaptationSeconds = 30;
stimulusSeconds = 40;
smoothingSeconds = 0.5;

if nargin < 1 || isempty(dataFile)
    startFolder = fullfile(pwd, 'data');
    if ~isfolder(startFolder)
        startFolder = pwd;
    end
    [fileName, folderName] = uigetfile({'*.mat', 'MATLAB data files (*.mat)'}, ...
        'Select an experiment data file', startFolder);
    if isequal(fileName, 0)
        outputDirectory = '';
        return;
    end
    dataFile = fullfile(folderName, fileName);
end

assert(isfile(dataFile), 'Data file not found: %s', dataFile);
loadedData = load(dataFile, 'gazeData', 'trialLog', 'metadata', 'cfg');
assert(isfield(loadedData, 'gazeData') && isfield(loadedData, 'trialLog') && ...
    isfield(loadedData, 'metadata'), ...
    'The selected file must contain gazeData, trialLog, and metadata.');
[timestampsUS, pupilMM] = pupilSeries(loadedData.gazeData);
firstTimestampUS = timestampsUS(find(isfinite(timestampsUS), 1, 'first'));
sampleTimeSeconds = (timestampsUS - firstTimestampUS) ./ 1e6;
sampleRateHz = getSampleRate(loadedData, sampleTimeSeconds);
smoothingSamples = max(1, round(smoothingSeconds * sampleRateHz));

[dataFolder, dataName] = fileparts(dataFile);
outputDirectory = fullfile(dataFolder, [dataName '_pupil_windows']);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

for iTrial = 1:numel(loadedData.trialLog)
    trial = loadedData.trialLog(iTrial);
    trialColorRGB = getTrialColorRGB(trial);
    if isfield(trial, 'tobiiSystemOnsetUS') && isfinite(trial.tobiiSystemOnsetUS)
        % Direct timestamp: same Tobii system clock as gaze samples.
        % 瞳孔サンプルと同じTobiiの時刻系を使って刺激開始からの時間を計算します。
        relativeTime = (timestampsUS - double(trial.tobiiSystemOnsetUS)) ./ 1e6;
    else
        % Compatibility path for recordings made before event timestamps
        % were added to the experiment program.
        % タイムスタンプ追加前に記録したデータ用の互換処理です。
        assert(isfield(loadedData.metadata, 'recordingStartPTB') && ...
            isfinite(loadedData.metadata.recordingStartPTB), ...
            ['This file has no usable event timestamp. Record a new session ', ...
             'with the updated experiment program.']);
        onsetSeconds = trial.stimulusOnsetPTB - loadedData.metadata.recordingStartPTB;
        relativeTime = sampleTimeSeconds - onsetSeconds;
    end
    inWindow = relativeTime >= -darkAdaptationSeconds & relativeTime <= stimulusSeconds;
    assert(any(inWindow), 'No pupil samples found for trial %d.', iTrial);

    windowTime = relativeTime(inWindow);
    windowPupil = pupilMM(inWindow);
    smoothedPupil = movmean(windowPupil, smoothingSamples, 'omitnan');
    color = double(trialColorRGB) ./ 255;

    figureHandle = figure('Color', 'w', 'Visible', 'off');
    plot(windowTime, smoothedPupil, 'k-', 'LineWidth', 1.4);
    grid on;
    xlim([-darkAdaptationSeconds stimulusSeconds]);
    ylim([2 7]);
    xlabel('Time relative to color onset (s)');
    ylabel('Mean pupil diameter (mm)');
    title(sprintf('Trial %d: RGB [%d %d %d]', iTrial, trialColorRGB), ...
        'Interpreter', 'none');
    hold on;
    xline(0, '--', 'Stimulus onset', 'LabelVerticalAlignment', 'bottom');
    % Show the stimulus color as a compact swatch in the upper-right corner.
    % 刺激色は右上の小さな色見本で示し、凡例や背景の塗りつぶしは使いません。
    annotation(figureHandle, 'rectangle', [0.86 0.84 0.035 0.035], ...
        'FaceColor', color, 'EdgeColor', 'k', 'LineWidth', 0.8);

    imageName = sprintf('trial_%02d_RGB_%03d_%03d_%03d.png', ...
        iTrial, trialColorRGB(1), trialColorRGB(2), trialColorRGB(3));
    imagePath = availableImagePath(outputDirectory, imageName);
    exportgraphics(figureHandle, imagePath, 'Resolution', 200);
    close(figureHandle);
end

fprintf('Saved %d pupil-window graphs to:\n%s\n', numel(loadedData.trialLog), outputDirectory);
end

function imagePath = availableImagePath(outputDirectory, imageName)
% Do not overwrite an existing PNG, which may be locked by OneDrive/viewer.
% 既存PNGを上書きせず、OneDriveや画像ビューアによるファイルロックを避けます。
imagePath = fullfile(outputDirectory, imageName);
if ~isfile(imagePath)
    return;
end

[~, imageBase, imageExtension] = fileparts(imageName);
versionNumber = 2;
while true
    candidateName = sprintf('%s_v%02d%s', imageBase, versionNumber, imageExtension);
    imagePath = fullfile(outputDirectory, candidateName);
    if ~isfile(imagePath)
        return;
    end
    versionNumber = versionNumber + 1;
end
end

function colorRGB = getTrialColorRGB(trial)
% Read new recordings and recordings made before colorRGB was renamed.
% 新しい記録と、フィールド名変更前の記録の両方を読み込みます。
if isfield(trial, 'colorRGB')
    colorRGB = trial.colorRGB;
elseif isfield(trial, 'colourRGB')
    colorRGB = trial.colourRGB;
else
    error('PlotPupilWindowsByColor:ColorNotFound', ...
        'trialLog does not contain colorRGB.');
end
end

function [timestampsUS, pupilMM] = pupilSeries(gazeData)
required = {'systemTimeStampUS', 'leftPupilDiameterMM', 'rightPupilDiameterMM'};
assert(isstruct(gazeData) && all(isfield(gazeData, required)), ...
    'gazeData does not contain numeric pupil time-series fields.');

timestampsUS = double(gazeData.systemTimeStampUS(:));
leftPupilMM = double(gazeData.leftPupilDiameterMM(:));
rightPupilMM = double(gazeData.rightPupilDiameterMM(:));
assert(numel(timestampsUS) == numel(leftPupilMM) && ...
    numel(timestampsUS) == numel(rightPupilMM), ...
    'Pupil and timestamp arrays must have the same length.');

assert(any(isfinite(timestampsUS)), 'No valid pupil timestamps were found.');

pupilMM = leftPupilMM;
bothValid = isfinite(leftPupilMM) & isfinite(rightPupilMM);
rightOnly = ~isfinite(leftPupilMM) & isfinite(rightPupilMM);
pupilMM(bothValid) = mean([leftPupilMM(bothValid), rightPupilMM(bothValid)], 2);
pupilMM(rightOnly) = rightPupilMM(rightOnly);
end

function sampleRateHz = getSampleRate(loadedData, sampleTimeSeconds)
if isfield(loadedData, 'cfg') && isfield(loadedData.cfg, 'samplingFrequencyHz')
    sampleRateHz = loadedData.cfg.samplingFrequencyHz;
    return;
end
intervals = diff(sampleTimeSeconds);
intervals = intervals(isfinite(intervals) & intervals > 0);
sampleRateHz = 1 / median(intervals);
end
