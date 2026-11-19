function run_single_color_pupil_experiment
% RUN_SINGLE_COLOR_PUPIL_EXPERIMENT Present one color channel at 7 digits.
% 1つの色チャンネルを、7段階のディジットで提示する瞳孔実験です。
%
% The timing, breaks, fixation cross, Tobii recording, and saved-data
% format match run_color_pupil_experiment.m. Change cfg.singleColorChannel
% below to 'red', 'green', 'blue', or 'gray' before running a different color.
% 提示時間・休憩・固視点・Tobii記録・保存形式は既存の実験と同じです。

cfg = singleColorConfig();
run_color_pupil_experiment(cfg);
end

function cfg = singleColorConfig()
% --- Edit these settings before an experimental session. ---
% --- 実験セッション前に、この設定を編集してください。 ---
cfg.participantId = 'SR002';
cfg.mode = 'production';                           % 'test' or 'production'
cfg.screenNumber = 0;                        % PTB screen ID.
cfg.skipSyncTests = true;                    % Set false only after sync is verified.
cfg.sdkRoot = '';                            % Optional Tobii SDK folder.
cfg.trackerModel = 'Tobii Pro Nano';
cfg.samplingFrequencyHz = 60;

% Select one color channel: 'red', 'green', 'blue', or 'gray'.
% 使用する色を 'red'、'green'、'blue'、'gray' から1つ選択します。
cfg.singleColorChannel = 'red';
% Each digit is presented once in randomized order.
% 各ディジットを1回ずつ、ランダムな順番で提示します。
cfg.stimulusDigits = [0 25 51 102 153 204 255];
cfg.stimuliRGB = makeSingleChannelStimuli( ...
    cfg.singleColorChannel, cfg.stimulusDigits);
cfg.fixationCrossDigitOffset = 30;          % Fixation digit = stimulus digit +/- 30.／固視点は刺激±30

cfg.stimulusSeconds = 40.0;                 % Color st  imulus duration: 40 s.／色刺激：40秒
cfg.interTrialSeconds = 30.0;               % Black screen duration: 30 s.／黒画面：30秒
cfg.preRunFixationSeconds = 30.0;           % Initial dark-adaptation period.／開始前暗順応：30秒
cfg.breakEveryTrials = 0;                   % No rest breaks.／単色実験では休憩なし
cfg.breakSeconds = 60.0;                     % Used only when breaks are enabled.／休憩を有効にした場合のみ使用
cfg.backgroundRGB = [0 0 0];
cfg.fixationCrossRGB = [30 30 30];          % Dark-screen and zero-stimulus fixation.／暗順応・ゼロ刺激用
cfg.fixationCrossHalfLengthPixels = 12;
cfg.fixationCrossLineWidthPixels = 3;
cfg.textFont = 'Yu Gothic UI';
cfg.textRGB = [255 255 255];
cfg.textSize = 28;
cfg.outputDirectory = fullfile(pwd, 'data');
end

function stimuliRGB = makeSingleChannelStimuli(colorChannel, digits)
% Convert the chosen color channel and digit list into N-by-3 RGB values.
% 選んだ色チャンネルとディジット列から、N行3列のRGB値を作成します。
assert(ischar(colorChannel) || isstring(colorChannel), ...
    'singleColorChannel must be ''red'', ''green'', ''blue'', or ''gray''.');
assert(isnumeric(digits) && isvector(digits) && ~isempty(digits) && ...
    all(isfinite(digits)) && all(digits >= 0 & digits <= 255), ...
    'stimulusDigits must contain values from 0 to 255.');

channelNames = {'red', 'green', 'blue'};
if strcmpi(char(colorChannel), 'gray')
    stimuliRGB = repmat(reshape(digits, [], 1), 1, 3);
    return;
end
channelIndex = find(strcmpi(char(colorChannel), channelNames), 1);
assert(~isempty(channelIndex), ...
    'singleColorChannel must be ''red'', ''green'', ''blue'', or ''gray''.');

stimuliRGB = zeros(numel(digits), 3);
stimuliRGB(:, channelIndex) = reshape(digits, [], 1);
end
