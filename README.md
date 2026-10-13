# Tobii Pro Nano 色刺激・瞳孔記録実験

`run_color_pupil_experiment.m` は、Psychtoolboxで全画面の色刺激を提示し、Tobii Pro Nanoで得た左右眼の瞳孔径を記録するMATLABプログラムです。

## 実験の流れ

1. 開始画面でSpaceを押す（Escで中止）。
2. 本番モードではTobiiの記録を開始する。
3. 初期暗順応として黒画面を30秒提示する。
4. 色をランダム順で提示する。1セットは次のとおりです。
   - 色刺激：40秒
   - 黒画面：30秒
5. 記録したデータと提示時刻をMATファイルに保存する。

提示時間は`run_color_pupil_experiment.m`の`defaultConfig`で設定します。

```matlab
cfg.stimulusSeconds = 40.0;       % 色刺激の秒数
cfg.interTrialSeconds = 30.0;     % 黒画面の秒数
cfg.preRunFixationSeconds = 30.0; % 最初の暗順応時間
```

## モードの切り替え

`defaultConfig` の `cfg.mode` を変更します。

```matlab
cfg.mode = 'test';         % Tobiiなし。描画・提示時間の確認用
% cfg.mode = 'production'; % Tobii Pro Nanoを使う本番記録用
```

`test`モードはTobiiに接続しません。刺激提示と試行ログは確認できますが、瞳孔データの`gazeData`は空です。

`production`モードでは、Tobii Pro SDK MATLAB Bindingを読み込め、かつTobii Pro Nanoが1台検出できる場合にだけ実験を開始します。

## 本番モードの準備

1. [Psychtoolbox-3](https://psychtoolbox.org/) と [Tobii Pro SDK MATLAB Binding](https://developer.tobiipro.com/matlab/matlab-getting-started.html) をMATLABに導入します。
2. Tobii Pro Eye Tracker ManagerでNanoが認識され、キャリブレーション済みであることを確認します。
3. SDKがMATLABパスにない場合は、SDKフォルダを指定します。

   ```matlab
   cfg.sdkRoot = 'C:\tools\TobiiProSDK'; % 実際の保存先に変更
   ```

4. 実験モニタは、`Screen('Screens')` で確認したPsychtoolboxの画面番号を指定します。

   ```matlab
   cfg.screenNumber = 1;
   ```

Windowsのディスプレイ番号とPsychtoolboxの画面番号は一致しないことがあります。外部モニタを使う場合は、Windowsで「拡張」表示に設定したうえで`Screen('Screens')`の結果を確認してください。

## 色刺激の編集

`cfg.stimuliRGB`の各行が1色です。値は`[R G B]`、範囲は各0〜255です。

```matlab
cfg.stimuliRGB = [
    255   0   0;
      0 255   0;
      0   0 255;
];
```

## 実行

このフォルダをMATLABのカレントフォルダにして実行します。

```matlab
run_color_pupil_experiment
```

同期テストが失敗してウィンドウを開けない環境では、必要な場合のみ次を設定できます。

```matlab
cfg.skipSyncTests = true;
```

この設定では実験を続行できますが、`Screen('Flip')`の提示時刻精度は保証されません。本番測定では、可能なら`false`のまま同期テストを通してください。

## 保存されるデータ

結果は`data/`フォルダにMATファイルとして保存されます。

| 変数 | 内容 |
| --- | --- |
| `gazeData.systemTimeStampUS` | 各瞳孔サンプルのTobiiシステム時刻（µs） |
| `gazeData.deviceTimeStampUS` | 各瞳孔サンプルのTobiiデバイス時刻（µs） |
| `gazeData.leftPupilDiameterMM` | 左眼瞳孔径（mm） |
| `gazeData.rightPupilDiameterMM` | 右眼瞳孔径（mm） |
| `trialLog` | 試行番号、色RGB、刺激・黒画面への切替時刻 |
| `cfg` / `metadata` | 実験設定とセッション情報 |

各試行の`trialLog`には、次の時刻が保存されます。

| フィールド | 内容 |
| --- | --- |
| `stimulusOnsetPTB` | 色刺激を画面に提示したPsychtoolbox時刻 |
| `tobiiSystemOnsetUS` | 色刺激提示直後に取得したTobiiシステム時刻 |
| `stimulusOffsetPTB` | 黒画面へ切り替えたPsychtoolbox時刻 |
| `tobiiSystemOffsetUS` | 黒画面への切替直後に取得したTobiiシステム時刻 |

`tobiiSystemOnsetUS`と`gazeData.systemTimeStampUS`は同じTobiiの時刻系です。解析時には、これらを使って各瞳孔サンプルを刺激開始からの時間へ変換できます。

## 解析用プログラム

### 全体の時系列グラフ

`plot_pupil_timeseries` は右眼瞳孔径を分単位の時系列として表示します。23分程度の記録を見やすくするため、横1600×縦700の横長ウィンドウで表示します。

```matlab
plot_pupil_timeseries
```

### 色ごとの瞳孔径グラフ

`plot_pupil_windows_by_color` は、各色について刺激開始の前30秒と後40秒を切り出し、両眼の有効な瞳孔径の平均を0.5秒移動平均でPNG出力します。時刻の対応には、`tobiiSystemOnsetUS`を優先して使います。

```matlab
plot_pupil_windows_by_color
```

この解析ファイル内の`darkAdaptationSeconds`と`stimulusSeconds`は、実験側の黒画面・色刺激の秒数と一致させてください。

### 瞳孔径CSVの書き出し

`export_pupil_diameter` は左右眼の瞳孔径だけをCSVの2列として出力します。時刻や試行情報は含まれないため、刺激別解析や周波数解析には、CSVではなく元のMATファイルを使用してください。

```matlab
export_pupil_diameter
```

### 刺激RGBと輝度の書き出し

`export_stimulus_luminance` は、実験MATファイルの実際の提示順と、SpecbosのLUTに保存された`iRGB`・`Luminance`を完全一致で照合します。試行番号、RGBデジット値、輝度（cd/m²）を`*_stimulus_luminance.csv`として保存します。

```matlab
export_stimulus_luminance
```

最初に実験データMATファイルを選びます。プロジェクト直下にSpecbosの`SpecbosData-*.mat`が1つだけある場合は、それを自動で使用します。

## 解析時の注意

- `test`モードのデータには瞳孔サンプルがないため、瞳孔解析には使えません。
- 欠損した瞳孔値は`NaN`として扱われます。刺激ごとの欠損率を確認してください。
- 周波数解析では、公称60 Hzではなく`gazeData.systemTimeStampUS`から実際のサンプル時刻を確認して処理してください。
- 事前に、実際のモニタ・距離・室内照明で短いパイロット測定を行い、欠損率と色ごとの輝度差を確認してください。
