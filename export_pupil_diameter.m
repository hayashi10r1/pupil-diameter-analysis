function outputFile = export_pupil_diameter(dataFile)
% EXPORT_PUPIL_DIAMETER Create a CSV containing left/right pupil diameter.
%
% Each output row is one pair of pupil-diameter samples in mm. The first
% column is left pupil; the second column is right pupil. No timestamps or
% gaze coordinates are included.
%
% Usage:
%   export_pupil_diameter
%   outputFile = export_pupil_diameter('C:\path\to\recording.mat')

if nargin < 1 || isempty(dataFile)
    startFolder = fullfile(pwd, 'data');
    if ~isfolder(startFolder)
        startFolder = pwd;
    end
    [fileName, folderName] = uigetfile({'*.mat', 'MATLAB data files (*.mat)'}, ...
        'Select an experiment data file', startFolder);
    if isequal(fileName, 0)
        outputFile = '';
        return;
    end
    dataFile = fullfile(folderName, fileName);
end

assert(isfile(dataFile), 'Data file not found: %s', dataFile);
loadedData = load(dataFile, 'gazeData');
assert(isfield(loadedData, 'gazeData') && isstruct(loadedData.gazeData) && ...
    isfield(loadedData.gazeData, 'leftPupilDiameterMM') && ...
    isfield(loadedData.gazeData, 'rightPupilDiameterMM'), ...
    'The selected file does not contain numeric left/right pupil diameter data.');

leftPupilDiameterMM = double(loadedData.gazeData.leftPupilDiameterMM(:));
rightPupilDiameterMM = double(loadedData.gazeData.rightPupilDiameterMM(:));
assert(numel(leftPupilDiameterMM) == numel(rightPupilDiameterMM), ...
    'Left and right pupil-diameter arrays must have the same length.');

[folderName, fileName] = fileparts(dataFile);
outputFile = fullfile(folderName, [fileName '_pupil_diameter.csv']);
writematrix([leftPupilDiameterMM, rightPupilDiameterMM], outputFile);

fprintf('Saved %d left/right pupil-diameter sample pairs to:\n%s\n', ...
    numel(leftPupilDiameterMM), outputFile);
end
