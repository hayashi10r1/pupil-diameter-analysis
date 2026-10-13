function outputFile = export_stimulus_luminance(experimentFile, calibrationFile)
% EXPORT_STIMULUS_LUMINANCE Export RGB digits and calibrated luminance.
% 実験で提示したRGBデジット値と、SpecbosのLUTから得た輝度をCSVに出力します。
%
% Usage:
%   export_stimulus_luminance
%   export_stimulus_luminance('C:\path\to\recording.mat')
%   export_stimulus_luminance('C:\path\to\recording.mat', ...
%       'C:\path\to\SpecbosData-2026-09-01-18-30.mat')

if nargin < 1 || isempty(experimentFile)
    experimentFile = selectMatFile(pwd, '実験データMATファイルを選択');
    if isempty(experimentFile)
        outputFile = '';
        return;
    end
end
assert(isfile(experimentFile), 'Experiment data file not found: %s', experimentFile);

if nargin < 2 || isempty(calibrationFile)
    calibrationFile = findOrSelectCalibrationFile();
    if isempty(calibrationFile)
        outputFile = '';
        return;
    end
end
assert(isfile(calibrationFile), 'Specbos calibration file not found: %s', calibrationFile);

experimentData = load(experimentFile, 'trialLog', 'cfg');
[trialNumber, stimulusRGB] = getStimulusRGB(experimentData);

calibrationData = load(calibrationFile, 'iRGB', 'Luminance');
assert(isfield(calibrationData, 'iRGB') && isfield(calibrationData, 'Luminance'), ...
    'The calibration file must contain iRGB and Luminance.');
lutRGB = double(calibrationData.iRGB);
lutLuminance = double(calibrationData.Luminance(:));
assert(size(lutRGB, 2) == 3 && size(lutRGB, 1) == numel(lutLuminance), ...
    'iRGB must be an N-by-3 array and Luminance must have N values.');

% The LUT is matched by exact RGB digits, not by nearest color.
% LUTは近い色ではなく、完全一致するRGBデジット値で照合します。
luminanceCdM2 = nan(size(trialNumber));
for iTrial = 1:numel(trialNumber)
    matches = all(lutRGB == stimulusRGB(iTrial, :), 2);
    if any(matches)
        luminanceCdM2(iTrial) = mean(lutLuminance(matches), 'omitnan');
    else
        warning('ExportStimulusLuminance:RGBNotInLUT', ...
            'No LUT entry for trial %d: RGB [%d %d %d].', ...
            trialNumber(iTrial), stimulusRGB(iTrial, :));
    end
end

resultTable = table(trialNumber, stimulusRGB(:, 1), stimulusRGB(:, 2), ...
    stimulusRGB(:, 3), luminanceCdM2, ...
    'VariableNames', {'Trial', 'RedDigit', 'GreenDigit', 'BlueDigit', ...
    'Luminance_cd_m2'});

[experimentFolder, experimentName] = fileparts(experimentFile);
outputFile = fullfile(experimentFolder, [experimentName '_stimulus_luminance.csv']);
writetable(resultTable, outputFile);

disp(resultTable);
fprintf('Saved stimulus luminance table to:\n%s\n', outputFile);

if any(isnan(luminanceCdM2))
    warning('ExportStimulusLuminance:MissingLuminance', ...
        'Some RGB values were not found in the LUT and were written as NaN.');
end
end

function [trialNumber, stimulusRGB] = getStimulusRGB(experimentData)
% Prefer the actual trial log, which preserves the presented random order.
% 実際のランダム提示順を保持するため、trialLogを優先して使います。
if isfield(experimentData, 'trialLog') && ~isempty(experimentData.trialLog) && ...
        all(isfield(experimentData.trialLog, 'trial'))
    trialNumber = reshape(double([experimentData.trialLog.trial]), [], 1);
    stimulusRGB = trialLogColorRGB(experimentData.trialLog);
elseif isfield(experimentData, 'cfg') && isfield(experimentData.cfg, 'stimuliRGB')
    stimulusRGB = experimentData.cfg.stimuliRGB;
    trialNumber = (1:size(stimulusRGB, 1))';
else
    error('ExportStimulusLuminance:StimuliNotFound', ...
        'The experiment file must contain trialLog or cfg.stimuliRGB.');
end

stimulusRGB = double(stimulusRGB);
assert(size(stimulusRGB, 2) == 3 && all(isfinite(stimulusRGB), 'all'), ...
    'Stimulus RGB values must be a finite N-by-3 array.');
end

function stimulusRGB = trialLogColorRGB(trialLog)
% Support recordings saved before colorRGB replaced the former field name.
if all(isfield(trialLog, 'colorRGB'))
    stimulusRGB = vertcat(trialLog.colorRGB);
elseif all(isfield(trialLog, 'colourRGB'))
    stimulusRGB = vertcat(trialLog.colourRGB);
else
    error('ExportStimulusLuminance:ColorNotFound', ...
        'trialLog does not contain colorRGB.');
end
end

function calibrationFile = findOrSelectCalibrationFile()
calibrationFiles = dir(fullfile(pwd, 'SpecbosData-*.mat'));
if numel(calibrationFiles) == 1
    calibrationFile = fullfile(calibrationFiles.folder, calibrationFiles.name);
    return;
end
calibrationFile = selectMatFile(pwd, 'SpecbosのLUT MATファイルを選択');
end

function selectedFile = selectMatFile(startFolder, dialogTitle)
[fileName, folderName] = uigetfile({'*.mat', 'MATLAB data files (*.mat)'}, ...
    dialogTitle, startFolder);
if isequal(fileName, 0)
    selectedFile = '';
else
    selectedFile = fullfile(folderName, fileName);
end
end
