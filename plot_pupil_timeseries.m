function plot_pupil_timeseries(dataFile)
% PLOT_PUPIL_TIMESERIES Display pupil diameter time series from an experiment MAT-file.
%
% Usage:
%   plot_pupil_timeseries
%   plot_pupil_timeseries('C:\path\to\recording.mat')
%
% The file must contain the `gazeData` structure saved by
% run_color_pupil_experiment.m.

if nargin < 1 || isempty(dataFile)
    startFolder = fullfile(pwd, 'data');
    if ~isfolder(startFolder)
        startFolder = pwd;
    end
    [fileName, folderName] = uigetfile({'*.mat', 'MATLAB data files (*.mat)'}, ...
        'Select an experiment data file', startFolder);
    if isequal(fileName, 0)
        return;
    end
    dataFile = fullfile(folderName, fileName);
end

assert(isfile(dataFile), 'Data file not found: %s', dataFile);
loadedData = load(dataFile, 'gazeData');
assert(isfield(loadedData, 'gazeData'), ...
    'The selected file does not contain gazeData.');

gazeData = loadedData.gazeData;
[timestampsUS, leftPupilMM, rightPupilMM] = extractPupilData(gazeData);
assert(numel(timestampsUS) == numel(leftPupilMM) && ...
    numel(timestampsUS) == numel(rightPupilMM), ...
    'Timestamp and pupil-diameter arrays must have the same length.');

validTime = isfinite(timestampsUS);
assert(any(validTime), 'No valid timestamps were found.');
timeMinutes = (timestampsUS - timestampsUS(find(validTime, 1, 'first'))) ./ (60 * 1e6);

[~, shortName, extension] = fileparts(dataFile);
figure('Color', 'w', 'Name', ['Pupil time series: ' shortName], ...
    'Position', [100 100 1600 700]);
plot(timeMinutes, rightPupilMM, '-', 'Color', [0.85 0.25 0.15], 'LineWidth', 1);
grid on;
xlabel('Time (min)');
ylabel('Pupil diameter (mm)');
title(['Right-pupil diameter time series: ' shortName extension], 'Interpreter', 'none');
legend({'Right pupil'}, 'Location', 'best');
end

function [timestampsUS, leftPupilMM, rightPupilMM] = extractPupilData(gazeData)
% Support both the numeric format currently saved by the experiment and
% directly loaded Tobii Pro SDK GazeData samples from earlier recordings.
numericFields = {'systemTimeStampUS', 'leftPupilDiameterMM', 'rightPupilDiameterMM'};
if isstruct(gazeData) && all(isfield(gazeData, numericFields))
    timestampsUS = double(gazeData.systemTimeStampUS(:));
    leftPupilMM = double(gazeData.leftPupilDiameterMM(:));
    rightPupilMM = double(gazeData.rightPupilDiameterMM(:));
    return;
end

if isa(gazeData, 'uint32')
    error('PlotPupilTimeSeries:UnreadableData', ...
        ['The saved GazeData objects could not be restored by MATLAB. ', ...
         'This file does not contain usable numeric pupil samples.']);
end

if ~isobject(gazeData)
    if isstruct(gazeData)
        availableFields = strjoin(fieldnames(gazeData), ', ');
    else
        availableFields = class(gazeData);
    end
    error('PlotPupilTimeSeries:UnsupportedData', ...
        'Unsupported gazeData format. Available fields/type: %s', availableFields);
end

nSamples = numel(gazeData);
timestampsUS = nan(nSamples, 1);
leftPupilMM = nan(nSamples, 1);
rightPupilMM = nan(nSamples, 1);
for iSample = 1:nSamples
    sample = gazeData(iSample);
    timestampsUS(iSample) = numericProperty(sample, 'SystemTimeStamp');
    leftPupilMM(iSample) = numericProperty( ...
        objectProperty(objectProperty(sample, 'LeftEye'), 'Pupil'), 'Diameter');
    rightPupilMM(iSample) = numericProperty( ...
        objectProperty(objectProperty(sample, 'RightEye'), 'Pupil'), 'Diameter');
end
end

function value = objectProperty(object, propertyName)
if isempty(object)
    value = [];
    return;
end
try
    value = object.(propertyName);
catch
    value = [];
end
end

function value = numericProperty(object, propertyName)
value = NaN;
rawValue = objectProperty(object, propertyName);
if isempty(rawValue)
    return;
end
try
    value = double(rawValue);
    if ~isscalar(value)
        value = NaN;
    end
catch
end
end
