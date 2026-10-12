function outputDirectory = plot_pupil_windows_by_colour(dataFile)
% PLOT_PUPIL_WINDOWS_BY_COLOUR Save one 70-second pupil plot for each colour.
%
% Each window spans 30 seconds of dark adaptation before stimulus onset and
% 40 seconds of colour stimulation after onset. Pupil size is the mean of
% the valid left- and right-eye diameter samples.
%
% Usage:
%   plot_pupil_windows_by_colour
%   plot_pupil_windows_by_colour('C:\path\to\recording.mat')

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
    colour = double(trial.colourRGB) ./ 255;

    figureHandle = figure('Color', 'w', 'Visible', 'off');
    plot(windowTime, smoothedPupil, 'k-', 'LineWidth', 1.4);
    grid on;
    xlim([-darkAdaptationSeconds stimulusSeconds]);
    xlabel('Time relative to colour onset (s)');
    ylabel('Mean pupil diameter (mm)');
    title(sprintf('Trial %d: RGB [%d %d %d]', iTrial, trial.colourRGB), ...
        'Interpreter', 'none');
    hold on;
    yLimits = ylim;
    stimulusPatch = patch([0 stimulusSeconds stimulusSeconds 0], ...
        [yLimits(1) yLimits(1) yLimits(2) yLimits(2)], colour, ...
        'FaceAlpha', 0.18, 'EdgeColor', 'none');
    uistack(stimulusPatch, 'bottom');
    xline(0, '--', 'Colour onset', 'LabelVerticalAlignment', 'bottom');
    legend({'Smoothed pupil diameter', 'Colour stimulus'}, 'Location', 'best');

    imageName = sprintf('trial_%02d_RGB_%03d_%03d_%03d.png', ...
        iTrial, trial.colourRGB(1), trial.colourRGB(2), trial.colourRGB(3));
    exportgraphics(figureHandle, fullfile(outputDirectory, imageName), 'Resolution', 200);
    close(figureHandle);
end

fprintf('Saved %d pupil-window graphs to:\n%s\n', numel(loadedData.trialLog), outputDirectory);
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
