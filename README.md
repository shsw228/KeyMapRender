# KeyMapRender

KeyMapRender プロジェクトの概要と運用情報を管理するための README です。
内容は今後の開発に合わせて更新します。

## 概要
- macOS 向けのキーマップオーバーレイ表示アプリ
- 特定キーの長押し中のみ、Vial/VIA 互換キーボードレイアウトを半透明オーバーレイで表示する

## セットアップ
- Xcode で `KeyMapRender.xcodeproj` を開く
- 初回起動時にアクセシビリティ権限を許可する

## 開発メモ
- 長押しキーコードと長押し時間はアプリ内フォームで設定可能
- レイアウト定義は `KeyMapRender/Resources/default-layout.json`
- 接続キーボード列挙と Vial Raw HID 通信テスト（protocol/layer/keycodeの最小取得）を実装
- `Rows/Cols` 指定で Vial dynamic keymap buffer（0x12）から全キー行列を取得可能
- LUCA移行の第一段として、依存注入基盤（DependencyClient / AppDependencies）を導入
- `luca --platform macOS` で生成した `LocalPackage` 雛形を取り込み済み（段階移行中）
- `KeyMapRender.xcodeproj` から `LocalPackage`（`DataSource`）を参照する構成へ接続済み
- `HIDKeyboardDevice` / `VialProbeResult` などの通信エンティティを `LocalPackage/Sources/DataSource/Entities` へ移設
- `HIDKeyboardClient` / `VialRawHIDClient` の依存契約を `LocalPackage/Sources/DataSource/Dependencies` へ移設
- アプリ実行時の依存コンテナを `Model.AppDependencies` ベースへ切替（アプリ側は live 実装注入のみ保持）
- 起動時設定（設定ウィンドウ自動表示）の状態管理を `Model/Stores/RootStore` へ移設開始
- `targetKeyCode` / `longPressDuration` / オーバーレイアニメーション / 無視デバイス設定の永続化を `RootStore` + `UserDefaultsRepository` 経由へ移行
- キーボード表示対象の選別（ignore適用）と選択ID解決・状態文言生成ロジックを `RootStore` へ移設
- Vial通信呼び出し（probe/readKeymap/inferMatrix/readDefinition/readSwitchMatrixState）を `RootStore` API 経由へ移設
- 診断ログ分類/キー診断メッセージ生成と `vial.json` 構造検証を `Model/Services` へ移設し、`ModelTests` を追加
- 起動時の matrix 自動推定→全マップ読出しフローを `RootStore.loadStartupKeymapAsync` に集約
- レイアウト選択肢の型を `Model.VialLayoutChoiceValue` に統一し、`AppModel` 側の重複定義を削除
- 自動起動設定（Launch at Login）を `LaunchAtLoginClient` 経由にし、`AppModel` からプラットフォームAPI直接依存を削減
- 権限確認（Accessibility/Input Monitoring）を `InputAccessClient` 経由へ移行
- クリップボード書き込みと `vial.json` 保存を `ClipboardClient` / `FileSaveClient` 経由へ移行
- キーボードホットプラグ監視を `HIDKeyboardHotplugClient` 経由へ移行
- 長押しキー監視を `GlobalKeyMonitorClient` + `RootStore` API 経由へ移行
- オーバーレイWindow表示制御を `OverlayWindowClient` + `RootStore` API 経由へ移行
- キーボードレイアウト生成ロジックを `Model.KeyboardLayoutService` へ移設（App側は委譲のみ）
- アクティブレイヤ追従ポーリング制御を `Model.ActiveLayerPollingService` へ移設
- 診断ログの追記整形を `Model.DiagnosticsLogBufferService` へ移設
- レイヤ選択のクランプ/変更判定を `Model.LayerSelectionService` へ移設
- キーボード再読込の選択補正/状態文言生成を `RootStore.refreshKeyboardSnapshot` に集約
- 起動時自動読込の表示文言生成を `RootStore.presentStartupKeymapLoadResult` に集約
- Vial通信テスト/全マップ読出し/matrix自動取得の表示文言生成を `RootStore` プレゼンテーションAPIへ集約
- レイヤ反映時のプレビュー/レイアウト/診断メッセージ生成を `Model.KeymapLayerRenderingService` へ集約
- `vial.json` エクスポートのファイル名/結果文言生成を `RootStore` プレゼンテーションAPIへ集約
- 権限状態/ターゲットキー入力検証/監視状態文言を `RootStore` APIへ集約
- キーボード未選択/読込中などの共通固定メッセージを `RootStore` APIへ集約
- オーバーレイ表示名とオーバーレイ/追従/ignore関連の診断メッセージ生成を `RootStore` APIへ集約
- 自動起動設定更新の診断メッセージ生成を `RootStore` APIへ集約
- Rows/Cols 入力パースと起動時初期matrix解決を `RootStore` APIへ集約
- Vial非同期ユースケース（probe/keymap/matrix/definition）の実行+表示統合を `RootStore` workflow APIへ移し、`AppModel` の条件分岐を縮小
- 起動時自動読込（matrix推定→keymap取得→表示文言）の実行+表示統合を `RootStore.runStartupKeymapLoadAsync` へ集約
- レイアウト選択肢生成/レイヤ描画は `RootStore` API 経由に統一し、`AppModel` から Service 直接依存を削減
- 診断ログの追記バッファ処理を `RootStore.appendDiagnosticsLog` へ移し、`AppModel` は表示反映とOSLog出力に専念
- `vial.json` エクスポート（取得→検証→保存）のユースケースを `RootStore.runExportVialDefinitionAsync` に集約

## ドキュメント
- 仕様書: `docs/specification.md`
