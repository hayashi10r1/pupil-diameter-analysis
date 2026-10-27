function run_color_pupil_experiment(cfg)
% RUN_COLOR_PUPIL_EXPERIMENT Present full-screen color stimuli while recording
% pupil data with a Tobii Pro Nano.
%
% Set cfg.mode to 'test' to run the display without a tracker.
% Set it to 'production' to require a connected Tobii Pro Nano through the
% official Tobii Pro SDK MATLAB Binding before the experiment can begin.
%
% The output MAT-file contains `gazeData`, including the raw gaze samples
% and left/right pupil diameters returned by the Tobii Pro SDK.
% Press Escape at any time to abort the run safely.
% An optional cfg structure can be passed from a specialized experiment.

if nargin < 1
    cfg = defaultConfig();
end
validateConfig(cfg);

% Make MATLAB able to find the Tobii Pro SDK MATLAB Binding, if needed.
% addpath(genpath('C:\path\to\TobiiProSDK-Matlab'));

AssertOpenGL;
KbName('UnifyKeyNames');
% Clear restrictions left by a previously interrupted Psychtoolbox task.
RestrictKeysForKbCheck([]);
oldVerbosity = Screen('Preference', 'Verbosity', 2);
oldSkipSyncTests = Screen('Preference', 'SkipSyncTests', double(cfg.skipSyncTests));
% Interpret text passed as UTF-8 so Japanese instructions can be displayed.
oldTextEncodingLocale = Screen('Preference', 'TextEncodingLocale', 'UTF-8');
cleanupObj = onCleanup(@() cleanupExperiment( ...
    oldVerbosity, oldSkipSyncTests, oldTextEncodingLocale)); %#ok<NASGU>
if cfg.skipSyncTests
    warning('ColorPupilExperiment:UnsyncedPresentation', ...
        ['Psychtoolbox synchronization tests are skipped. Stimulus onset ', ...
         'times are not guaranteed; do not interpret them as precise timing.']);
end

try
    %% Prepare display before starting SDK activity
    % Opening the full-screen window runs Psychtoolbox's VBL sync test. On
    % some Windows systems, SDK discovery running first can perturb it.
    screens = Screen('Screens');
    if ~ismember(cfg.screenNumber, screens)
        error('ColorPupilExperiment:DisplayNotFound', ...
            'Psychtoolbox screen %d was requested, but available screen numbers are: [%s].', ...
            cfg.screenNumber, num2str(screens));
    end
    screenNumber = cfg.screenNumber;
    fprintf('Psychtoolbox screens: [%s]. Stimulus screen: %d.\n', num2str(screens), screenNumber);
    % Keep Psychtoolbox's native 0--255 color range: cfg.stimuliRGB
    % values are specified in standard 8-bit notation.
    PsychDefaultSetup(1);
    % No imaging-pipeline tasks are needed for simple full-screen colors.
    % Screen('OpenWindow') also avoids stale PsychImaging configuration left
    % behind by an earlier aborted startup.
    [window, windowRect] = Screen('OpenWindow', screenNumber, cfg.backgroundRGB);
    Screen('TextSize', window, cfg.textSize);
    Screen('TextFont', window, cfg.textFont);
    HideCursor(window);
    Priority(MaxPriority(window));

    %% Connect to tracker only in production mode
    eyeTracker = [];
    tobiiOperations = [];
    if strcmp(cfg.mode, 'production')
        [eyeTracker, tobiiOperations] = connectProductionTracker(cfg);
        trackerCleanup = onCleanup(@() stopGazeDataSafely(eyeTracker)); %#ok<NASGU>
    end

    if strcmp(cfg.mode, 'production')
        startMessage = 'Press SPACE or ENTER to begin.\nPress ESC to cancel.';
    else
        startMessage = 'TEST MODE: no Tobii recording.\nPress SPACE to check the display.\nPress ESC to cancel.';
    end
    drawCenteredText(window, startMessage, cfg.textRGB);
    Screen('Flip', window);
    waitForKey({'space','return'});

    %% Record and present trials
    Screen('FillRect', window, cfg.backgroundRGB, windowRect);
    drawFixationCross(window, windowRect, cfg);
    Screen('Flip', window);
    recordingStartPTB = NaN;
    if strcmp(cfg.mode, 'production')
        % The first call starts background collection in the official SDK.
        recordingStartPTB = GetSecs;
        eyeTracker.get_gaze_data();
    end
    WaitSecs(cfg.preRunFixationSeconds);

    % One trial consists of a color screen followed by a black screen.
    % 1試行（1セット）は、色刺激40秒の後に黒画面30秒を提示します。
    trialOrder = randperm(size(cfg.stimuliRGB, 1));
    trialLog = repmat(struct('trial', [], 'colorRGB', [], ...
        'stimulusOnsetPTB', [], 'stimulusOffsetPTB', [], ...
        'tobiiSystemOnsetUS', [], 'tobiiSystemOffsetUS', []), ...
        1, numel(trialOrder));

    for iTrial = 1:numel(trialOrder)
        color = cfg.stimuliRGB(trialOrder(iTrial), :);

        Screen('FillRect', window, color, windowRect);
        drawFixationCross(window, windowRect, cfg);
        onset = Screen('Flip', window);
        % `onset` is the Psychtoolbox visual-onset timestamp. Take a
        % Tobii-system-clock marker immediately afterwards so that this
        % event can be aligned with gazeData.systemTimeStampUS.
        % `onset` はPsychtoolboxが返す色刺激の提示開始時刻です。
        % 直後にTobiiのシステム時刻も取得し、瞳孔データの
        % gazeData.systemTimeStampUS と対応づけます。
        tobiiSystemOnsetUS = NaN;
        if strcmp(cfg.mode, 'production')
            tobiiSystemOnsetUS = double(tobiiOperations.get_system_time_stamp());
        end
        waitUntilOrAbort(onset + cfg.stimulusSeconds);

        Screen('FillRect', window, cfg.backgroundRGB, windowRect);
        drawFixationCross(window, windowRect, cfg);
        offset = Screen('Flip', window);
        % This is the start of the 30-second black screen.
        % 黒画面30秒の開始時刻（＝色刺激の終了時刻）も記録します。
        tobiiSystemOffsetUS = NaN;
        if strcmp(cfg.mode, 'production')
            tobiiSystemOffsetUS = double(tobiiOperations.get_system_time_stamp());
        end
        trialLog(iTrial) = struct('trial', iTrial, 'colorRGB', color, ...
            'stimulusOnsetPTB', onset, 'stimulusOffsetPTB', offset, ...
            'tobiiSystemOnsetUS', tobiiSystemOnsetUS, ...
            'tobiiSystemOffsetUS', tobiiSystemOffsetUS);

        waitUntilOrAbort(offset + cfg.interTrialSeconds);

        % Insert a one-minute rest after each completed block of trials,
        % except after the final trial of the experiment.
        % 5トライアルごとに1分間の休憩を入れます（最終試行後を除く）。
        if mod(iTrial, cfg.breakEveryTrials) == 0 && iTrial < numel(trialOrder)
            runRestBreak(window, cfg, iTrial, numel(trialOrder));
            runPostBreakDarkAdaptation(window, windowRect, cfg);
        end
    end

    if strcmp(cfg.mode, 'production')
        % This call returns all samples accumulated since recording started.
        rawGazeData = eyeTracker.get_gaze_data();
        eyeTracker.stop_gaze_data();
        % SDK GazeData objects cannot reliably be restored from MAT-files.
        % Convert to ordinary numeric arrays before saving.
        gazeData = makeSaveableGazeData(rawGazeData);
    else
        gazeData = [];
    end

    %% Save samples (production) and timing markers (both modes) together
    metadata = struct( ...
        'participantId', cfg.participantId, ...
        'sessionStarted', datetime('now'), ...
        'mode', cfg.mode, ...
        'syncTestsSkipped', logical(cfg.skipSyncTests), ...
        'recordingStartPTB', recordingStartPTB, ...
        'eventTimestampSource', 'Tobii Pro SDK system clock (microseconds)', ...
        'trackerModel', cfg.trackerModel, ...
        'samplingFrequencyHz', cfg.samplingFrequencyHz, ...
        'software', 'Psychtoolbox + Tobii Pro SDK MATLAB Binding');
    if ~exist(cfg.outputDirectory, 'dir')
        mkdir(cfg.outputDirectory);
    end
    fileStem = sprintf('%s_%s', cfg.participantId, datestr(now, 'yyyymmdd_HHMMSS'));
    outputFile = fullfile(cfg.outputDirectory, [fileStem '.mat']);
    save(outputFile, 'cfg', 'metadata', 'trialLog', 'gazeData', '-v7.3');

    drawCenteredText(window, sprintf('Finished (%s).\nSaved: %s\n\nPress SPACE or ENTER to close.', ...
        upper(cfg.mode), outputFile), cfg.textRGB);
    Screen('Flip', window);
    waitForKey({'space', 'return'});

catch exception
    % `onCleanup` closes the display. Re-throw so that MATLAB shows the
    % reason and preserves a useful debugging stack trace.
    rethrow(exception);
end
end

function [eyeTracker, operations] = connectProductionTracker(cfg)
% Discover the Nano with the official Tobii Pro SDK MATLAB Binding.
if ~isempty(cfg.sdkRoot)
    assert(isfolder(cfg.sdkRoot), 'Tobii Pro SDK folder not found: %s', cfg.sdkRoot);
    addpath(genpath(char(cfg.sdkRoot)));
end
if exist('EyeTrackingOperations', 'class') ~= 8
    error('ColorPupilExperiment:SDKUnavailable', ...
        ['Production mode requires the Tobii Pro SDK MATLAB Binding. ', ...
         'Add its folder to the MATLAB path before running this experiment.']);
end
try
    operations = EyeTrackingOperations();
    trackers = operations.find_all_eyetrackers();
catch exception
    error('ColorPupilExperiment:SDKConnectionFailed', ...
        'Could not search for Tobii eye trackers.\n\n%s', exception.message);
end

if isempty(trackers)
    error('ColorPupilExperiment:TrackerNotConnected', ...
        ['Production mode stopped: no Tobii eye tracker was found. ', ...
         'Check Tobii Pro Eye Tracker Manager and the USB/network connection.']);
end

models = arrayfun(@(tracker) string(tracker.Model), trackers);
matching = find(strcmpi(models, cfg.trackerModel));
if numel(matching) ~= 1
    error('ColorPupilExperiment:WrongTracker', ...
        'Expected exactly one %s, but found: %s.', cfg.trackerModel, strjoin(models, ', '));
end
eyeTracker = trackers(matching);
fprintf('Connected tracker: %s (serial: %s)\n', eyeTracker.Model, eyeTracker.SerialNumber);
end

function stopGazeDataSafely(eyeTracker)
% Ensure collection is stopped even if an error or Escape ends a run.
try
    eyeTracker.stop_gaze_data();
catch
end
end

function gazeData = makeSaveableGazeData(rawGazeData)
% Store only numeric SDK fields so the MAT-file is portable and reloadable.
nSamples = numel(rawGazeData);
gazeData = struct( ...
    'systemTimeStampUS', nan(nSamples, 1), ...
    'deviceTimeStampUS', nan(nSamples, 1), ...
    'leftPupilDiameterMM', nan(nSamples, 1), ...
    'rightPupilDiameterMM', nan(nSamples, 1));

for iSample = 1:nSamples
    sample = rawGazeData(iSample);
    gazeData.systemTimeStampUS(iSample) = numericSDKMember(sample, 'SystemTimeStamp');
    gazeData.deviceTimeStampUS(iSample) = numericSDKMember(sample, 'DeviceTimeStamp');
    gazeData.leftPupilDiameterMM(iSample) = numericSDKMember( ...
        sdkMember(sdkMember(sample, 'LeftEye'), 'Pupil'), 'Diameter');
    gazeData.rightPupilDiameterMM(iSample) = numericSDKMember( ...
        sdkMember(sdkMember(sample, 'RightEye'), 'Pupil'), 'Diameter');
end
end

function result = sdkMember(item, name)
if isstruct(item)
    if isfield(item, name)
        result = item.(name);
    else
        result = [];
    end
    return;
end
try
    result = item.(name);
catch
    result = [];
end
end

function value = numericSDKMember(item, name)
value = NaN;
rawValue = sdkMember(item, name);
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

function cfg = defaultConfig()
cfg.participantId = 'test101101';                 % Change before every session.
%cfg.mode = 'production';                          % 'test' or 'production'
cfg.mode = 'test';
cfg.screenNumber = 0 ;                       % PTB screen ID; usually external display.
cfg.skipSyncTests = true;                   % Allows presentation without timing guarantee.
cfg.sdkRoot = '';                            % Optional SDK folder, e.g. 'C:\tools\TobiiProSDK'.
cfg.trackerModel = 'Tobii Pro Nano';
cfg.samplingFrequencyHz = 60;               % Nano's nominal sample rate.
% Edit this list to change the stimuli. Each row is one [R G B] color.
% RGB values range from 0 to 255. Add a row to add a stimulus.
cfg.stimuliRGB = [
     51   0   0;
    102   0   0;
    153   0   0;
    204   0   0;
    255   0   0;
      0  51   0;
      0 102   0;
      0 153   0;
      0 204   0;
      0 255   0;
      0   0  51;
      0   0 102;
      0   0 153;
      0   0 204;
      0   0 255;
     51  51  51;
    102 102 102;  
    153 153 153;
    204 204 204;  
    255 255 255;
];
cfg.stimulusSeconds = 40.0;                 % Color stimulus duration: 40 s.（色刺激：40秒）
cfg.interTrialSeconds = 30.0;               % Black screen duration: 30 s.（黒画面：30秒）
cfg.preRunFixationSeconds = 30.0;           % Initial dark-adaptation period.
cfg.breakEveryTrials = 5;                   % Rest after every 5 trials.／5トライアルごとに休憩
cfg.breakSeconds = 60.0;                    % Rest duration in seconds.／休憩時間（秒）
cfg.backgroundRGB = [0 0 0];                % Inter-trial background (black).
cfg.fixationCrossRGB = [0 0 0];             % Fixation cross color (black).／固視点の色（黒）
cfg.fixationCrossHalfLengthPixels = 12;     % Half-length of each cross arm.／十字の各線の半分の長さ
cfg.fixationCrossLineWidthPixels = 3;       % Cross line width.／十字の線の太さ
cfg.textFont = 'Yu Gothic UI';               % Japanese-capable Windows font.／日本語対応フォント
cfg.textRGB = [255 255 255];
cfg.textSize = 28;
cfg.outputDirectory = fullfile(pwd, 'data');
end

function validateConfig(cfg)
assert(ischar(cfg.participantId) || isstring(cfg.participantId), 'participantId must be text.');
assert(any(strcmp(cfg.mode, {'test', 'production'})), ...
    "cfg.mode must be 'test' or 'production'.");
assert(isscalar(cfg.screenNumber) && cfg.screenNumber >= 0 && mod(cfg.screenNumber, 1) == 0, ...
    'screenNumber must be a non-negative integer Psychtoolbox screen ID.');
assert(isscalar(cfg.skipSyncTests) && any(cfg.skipSyncTests == [0 1]), ...
    'skipSyncTests must be true or false.');
assert(ischar(cfg.sdkRoot) || isstring(cfg.sdkRoot), 'sdkRoot must be text.');
assert(isnumeric(cfg.stimuliRGB) && size(cfg.stimuliRGB, 2) == 3 && ~isempty(cfg.stimuliRGB) && ...
    all(cfg.stimuliRGB(:) >= 0 & cfg.stimuliRGB(:) <= 255), ...
    'stimuliRGB must be a non-empty N-by-3 array with values from 0 to 255.');
assert(isnumeric(cfg.fixationCrossRGB) && numel(cfg.fixationCrossRGB) == 3 && ...
    all(cfg.fixationCrossRGB(:) >= 0 & cfg.fixationCrossRGB(:) <= 255), ...
    'fixationCrossRGB must be a three-element RGB value from 0 to 255.');
assert(isscalar(cfg.fixationCrossHalfLengthPixels) && cfg.fixationCrossHalfLengthPixels > 0 && ...
    isfinite(cfg.fixationCrossHalfLengthPixels), ...
    'fixationCrossHalfLengthPixels must be a positive number.');
assert(isscalar(cfg.fixationCrossLineWidthPixels) && cfg.fixationCrossLineWidthPixels > 0 && ...
    isfinite(cfg.fixationCrossLineWidthPixels), ...
    'fixationCrossLineWidthPixels must be a positive number.');
assert(cfg.stimulusSeconds > 0 && cfg.interTrialSeconds >= 0, 'Durations must be valid.');
assert(isscalar(cfg.breakEveryTrials) && cfg.breakEveryTrials >= 1 && ...
    mod(cfg.breakEveryTrials, 1) == 0, ...
    'breakEveryTrials must be a positive integer.');
assert(isscalar(cfg.breakSeconds) && cfg.breakSeconds >= 0 && isfinite(cfg.breakSeconds), ...
    'breakSeconds must be a non-negative number.');
assert(ischar(cfg.textFont) || isstring(cfg.textFont), 'textFont must be text.');
end

function waitForKey(allowedKeys)
% An event queue reliably catches brief Space/Escape presses in a full-screen
% Psychtoolbox window.  On Windows, the default queue represents the system
% keyboard; use a PTB device index here if a dedicated response box is used.
allowedKeyCodes = KbName(allowedKeys);
escapeKeyCode = KbName('ESCAPE');
keyList = zeros(1, 256);
keyList([allowedKeyCodes, escapeKeyCode]) = 1;
KbQueueCreate([], keyList);
KbQueueStart;
queueCleanup = onCleanup(@() releaseKeyboardQueue()); %#ok<NASGU>
while true
    [pressed, firstPress] = KbQueueCheck;
    if ~pressed
        WaitSecs(0.005);
        continue;
    end
    if firstPress(escapeKeyCode) > 0

        error('ColorPupilExperiment:Aborted', 'Experiment aborted by user.');
    end
    if any(firstPress(allowedKeyCodes) > 0)
        return;
    end
end
end

function waitUntilOrAbort(endTime)
% Poll Escape while retaining accurate stimulus offset scheduling.
escapeKeyCode = KbName('ESCAPE');
while GetSecs < endTime
    [keyIsDown, ~, keyCode] = KbCheck(-1);
    if keyIsDown && keyCode(escapeKeyCode)
        error('ColorPupilExperiment:Aborted', 'Experiment aborted by user.');
    end
    WaitSecs(0.005);
end
end

function releaseKeyboardQueue()
try
    KbQueueStop;
    KbQueueRelease;
catch
end
end

function drawCenteredText(window, message, color)
% Convert MATLAB text to UTF-8 bytes. This prevents Japanese text from
% being misinterpreted by Psychtoolbox on Windows.
% MATLABの文字列をUTF-8バイト列に変換し、Windows上で日本語が
% Psychtoolboxに誤って解釈されることを防ぎます。
utf8Message = unicode2native(char(message), 'UTF-8');
DrawFormattedText(window, utf8Message, 'center', 'center', color);
end

function drawFixationCross(window, windowRect, cfg)
% Draw a centered fixation cross over the currently prepared background.
% 現在描画している背景の中央に十字の固視点を重ねて描画します。
[xCenter, yCenter] = RectCenter(windowRect);
halfLength = cfg.fixationCrossHalfLengthPixels;
coordinates = [xCenter - halfLength, xCenter + halfLength, xCenter, xCenter; ...
               yCenter, yCenter, yCenter - halfLength, yCenter + halfLength];
Screen('DrawLines', window, coordinates, cfg.fixationCrossLineWidthPixels, cfg.fixationCrossRGB);
end

function runRestBreak(window, cfg, completedTrials, totalTrials)
% Present the rest message and update its 60-second countdown once per second.
% 休憩メッセージと、残り時間のカウントダウンを1秒ごとに表示します。
breakEndTime = GetSecs + cfg.breakSeconds;
lastShownSeconds = NaN;
while true
    remainingSeconds = max(0, ceil(breakEndTime - GetSecs));
    if remainingSeconds ~= lastShownSeconds
        Screen('FillRect', window, cfg.backgroundRGB);
        message = sprintf(['顎台から顎を外して楽にしてください\n\n' ...
            '進行状況: %d / %d トライアル完了\n' ...
            '休憩終了まで: %d 秒'], completedTrials, totalTrials, remainingSeconds);
        drawCenteredText(window, message, cfg.textRGB);
        Screen('Flip', window);
        lastShownSeconds = remainingSeconds;
    end

    if remainingSeconds <= 0
        return;
    end

    escapeKeyCode = KbName('ESCAPE');
    [keyIsDown, ~, keyCode] = KbCheck(-1);
    if keyIsDown && keyCode(escapeKeyCode)
        error('ColorPupilExperiment:Aborted', 'Experiment aborted by user.');
    end
    WaitSecs(0.01);
end
end

function runPostBreakDarkAdaptation(window, windowRect, cfg)
% Return to a black screen for dark adaptation before the next stimulus.
% 休憩後、次の色刺激の前に黒画面で暗順応を行います。
Screen('FillRect', window, cfg.backgroundRGB, windowRect);
drawFixationCross(window, windowRect, cfg);
darkAdaptationOnset = Screen('Flip', window);
waitUntilOrAbort(darkAdaptationOnset + cfg.interTrialSeconds);
end

function cleanupExperiment(oldVerbosity, oldSkipSyncTests, oldTextEncodingLocale)
Priority(0);
ShowCursor;
sca;
Screen('Preference', 'Verbosity', oldVerbosity);
Screen('Preference', 'SkipSyncTests', oldSkipSyncTests);
Screen('Preference', 'TextEncodingLocale', oldTextEncodingLocale);
end
