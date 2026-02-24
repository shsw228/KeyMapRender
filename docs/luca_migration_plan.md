# LUCA適合 移行計画（KeyMapRender）

## 1. 目的
- 既存の単一ターゲット構成（`AppModel` 中心）を、LUCAの3レイヤ構成へ段階移行する。
- 機能退行を避けつつ、責務分離・テスト容易性・将来拡張性を改善する。

## 2. 現状と課題
- 現状は `AppModel.swift` に状態管理・ユースケース・一部インフラ呼び出しが集中。
- `VialRawHIDService.swift` / `HIDKeyboardService.swift` は分離されているが、依存注入の統一ルールがない。
- View から `@EnvironmentObject AppModel` で広範囲に状態/操作へ直接アクセスしている。
- ロジック単体テストを追加しづらい。

## 3. LUCAへのマッピング

### DataSource
- `Entities`
  - `KeyboardLayout`（必要なら表示向けと通信向けを分離）
  - `HIDKeyboardDevice`
  - `VialProbeResult` / `VialKeymapDump` / `VialMatrixInfo` / `VialSwitchMatrixState`
- `Dependencies`
  - `VialRawHIDClient`（現 `VialRawHIDService` を client 化）
  - `HIDKeyboardClient`（現 `HIDKeyboardService` + hotplug 監視 API）
  - `GlobalKeyMonitorClient`（現 `GlobalKeyLongPressMonitor`）
  - `LaunchAtLoginClient`（`SMAppService`）
  - `UserDefaultsClient`
  - `LoggerClient`（`OSLog` 書き込み）
  - `OverlayWindowClient`（`OverlayWindowController` 呼び出し面）
- `Repositories`
  - `KeyboardRepository`（列挙・選択・ignore 管理）
  - `VialRepository`（probe/keymap/definition/matrix state）
  - `SettingsRepository`（targetKey/threshold/animation/起動設定）

### Model
- `AppDependencies`
  - 上記 DependencyClient を束ねる。
- `Services`
  - `VialDecodeService`（キーコード表示解釈・複合キーラベル生成）
  - `OverlayLayoutService`（表示レイヤ/分岐レイアウト反映）
  - `ActiveLayerTrackingService`（レイヤ追従ロジック）
- `Stores`
  - `SettingsStore`（設定タブ群の状態/イベント）
  - `OverlayStore`（長押し開始/終了、オーバーレイ表示制御）
  - `DiagnosticsStore`（ログ集約・コピー）
  - `RootStore`（現在の `AppModel` 相当。子Store委譲）

### UserInterface
- `Scenes`
  - `SettingsScene`（現 `ContentView` 系）
  - `MenuBarScene`
- `Views`
  - 既存 `GeneralSettingsView` / `VialSettingsView` / `StatusView` / `DiagnosticsView` / `HelpView` を Store注入型へ変更
  - `KeyboardOverlayView` は表示専用化

## 4. 段階移行（機能維持優先）

### Phase 0: 足場
- `LocalPackage` 追加（`DataSource`/`Model`/`UserInterface`）
- `AppDependencies` と `DependencyClient` 最小セットを作成
- 既存 target から package を参照
 - 状態: 2026-02-24 時点で `luca --platform macOS` 生成結果を取り込み、`KeyMapRender.xcodeproj` へ `LocalPackage(DataSource)` を接続済み

### Phase 1: インフラ抽出
- `VialRawHIDService` / `HIDKeyboardService` / `GlobalKeyLongPressMonitor` / `OverlayWindowController` を DependencyClient 経由へ
- 挙動を変えず `AppModel` 内呼び出し先のみ差し替え
- 状態: `HIDKeyboardDevice` / `Vial*` 応答型を `DataSource/Entities` へ移設し、アプリ側は `DataSource` の公開型を参照する構成へ更新済み
- 状態: `HIDKeyboardClient` / `VialRawHIDClient` の依存契約を `DataSource/Dependencies` へ移設し、アプリ側は live 実装の注入のみ保持
- 状態: アプリ側の依存コンテナ実装を削除し、`Model.AppDependencies` を実行時DIの基準へ切替済み

### Phase 2: Store分割
- `AppModel` を `RootStore` へ置換開始
- 設定系・診断系・オーバーレイ系を子Storeへ分離
- View は `EnvironmentObject` 依存を段階的に縮小
- 状態: 起動時設定（showSettingsOnLaunch）の判定/保存ロジックを `Model/Stores/RootStore` 経由へ移行済み
- 状態: `targetKeyCode` / `longPressDuration` / `overlayShowAnimationDuration` / `overlayHideAnimationDuration` / `ignoredDeviceIDs` の保存を `RootStore` + `UserDefaultsRepository` 経由へ移行済み
- 状態: キーボード一覧の ignore 適用・選択ID補正・状態文言生成を `RootStore` 側ロジックへ移行済み
- 状態: Vial通信クライアント実行（probe/keymap/matrix/definition/switch matrix）を `RootStore` 経由へ移行済み
- 状態: `HIDKeyboardDevice` を `Sendable` 化し、`RootStore` の通信APIを `nonisolated` で提供して並行実行時の警告を低減
- 状態: レイヤ追従判定ロジックを `Model/Services/ActiveLayerTrackingService` へ分離し、`AppModel` から純ロジックを削減
- 状態: `AppModel` の Vial 操作実行を `Task + RootStore` の非同期API呼び出しへ置換し、`DispatchQueue` 直書きを縮小
- 状態: キーマップ表示整形（プレビュー文字列・レイアウト選択肢生成）を `Model/Services/VialPresentationService` へ分離
- 状態: 診断ログ判定/キー診断文生成を `Model/Services/VialDiagnosticsService` へ分離
- 状態: `vial.json` 構造検証を `Model/Services/VialDefinitionValidationService` へ分離
- 状態: 上記 Service の回帰防止として `ModelTests` に単体テストを追加
- 状態: 起動時の matrix推定→keymap読込ユースケースを `RootStore.loadStartupKeymapAsync` へ移設
- 状態: `AppModel` ローカルの `VialLayoutChoice` を廃止し、`Model.VialLayoutChoiceValue` を直接参照する形に統一
- 状態: `RootStore` のキーボード選別/選択解決/状態文言ロジックに単体テストを追加
- 状態: 自動起動設定の依存を `LaunchAtLoginClient` + `RootStore` API へ移し、`AppModel` 直依存を削減
- 状態: 権限確認（Accessibility/Input Monitoring）を `InputAccessClient` + `RootStore` API へ移し、`AppModel` 直依存を削減
- 状態: クリップボード書き込みと保存ダイアログを `ClipboardClient` / `FileSaveClient` + `RootStore` API へ移し、`AppModel` 直依存を削減
- 状態: ホットプラグ監視を `HIDKeyboardHotplugClient` + `RootStore` API へ移し、`AppModel` の監視実体依存を削減
- 状態: 長押しキー監視を `GlobalKeyMonitorClient` + `RootStore` API へ移し、`AppModel` の監視実体依存を削減
- 状態: オーバーレイWindow表示制御を `OverlayWindowClient` + `RootStore` API へ移し、`AppModel` のWindow実体依存を削減
- 状態: キーボードレイアウト生成ロジックを `Model/Services/KeyboardLayoutService` へ移し、`AppModel` から実装詳細を分離
- 状態: アクティブレイヤ追従ポーリング制御を `Model/Services/ActiveLayerPollingService` へ移し、`AppModel` のループ責務を縮小
- 状態: 診断ログの文字列更新責務を `Model/Services/DiagnosticsLogBufferService` へ移し、`AppModel` の表示整形ロジックを縮小
- 状態: レイヤ選択のクランプ/変更判定を `Model/Services/LayerSelectionService` へ移し、`AppModel` の制御分岐を縮小
- 状態: キーボード再読込時の選択補正/状態文言生成を `RootStore.refreshKeyboardSnapshot` へ集約
- 状態: 起動時自動読込の表示文言生成を `RootStore.presentStartupKeymapLoadResult` へ集約
- 状態: Vial通信テスト/全マップ読出し/matrix自動取得の表示文言生成を `RootStore` プレゼンテーションAPIへ集約
- 状態: レイヤ反映時のプレビュー/レイアウト/診断メッセージ生成を `Model/Services/KeymapLayerRenderingService` へ移設
- 状態: `vial.json` エクスポートのファイル名/結果文言生成を `RootStore` プレゼンテーションAPIへ集約
- 状態: 権限状態/ターゲットキー入力検証/監視状態文言を `RootStore` APIへ集約
- 状態: キーボード未選択/読込中などの共通固定メッセージを `RootStore` APIへ集約
- 状態: オーバーレイ表示名とオーバーレイ/追従/ignore関連の診断メッセージ生成を `RootStore` APIへ集約
- 状態: 自動起動設定更新の診断メッセージ生成を `RootStore` APIへ集約
- 状態: Rows/Cols 入力パースと起動時初期matrix解決を `RootStore` APIへ集約
- 状態: Vial非同期ユースケース（probe/keymap/matrix/definition）を `RootStore` workflow API（実行+表示統合）へ集約し、`AppModel` の分岐を縮小
- 状態: 起動時自動読込ユースケース（matrix推定→keymap取得→表示文言）を `RootStore.runStartupKeymapLoadAsync` へ集約

### Phase 3: Service分離とテスト
- レイヤ追従・キーラベル解釈・レイアウト反映を Service へ抽出
- `ModelTests` に Service/Store テスト追加

### Phase 4: 完了整理
- 旧 `AppModel` を削除
- DataSource/Model/UserInterface の依存方向を固定

## 5. 既存ファイル対応表
- `AppModel.swift` → `Model/Stores/RootStore.swift` + 子Store群へ分割
- `VialRawHIDService.swift` → `DataSource/Dependencies/VialRawHIDClient.swift`
- `HIDKeyboardService.swift` → `DataSource/Dependencies/HIDKeyboardClient.swift`
- `HIDKeyboardHotplugMonitor.swift` → `DataSource/Dependencies/HIDKeyboardClient` 内部
- `OverlayWindowController.swift` → `DataSource/Dependencies/OverlayWindowClient.swift`
- `GlobalKeyLongPressMonitor.swift` → `DataSource/Dependencies/GlobalKeyMonitorClient.swift`
- `KeyboardLayout.swift` → Entity層 + UI拡張へ再配置
- `*View.swift` 群 → `UserInterface/Views`

## 6. 先に決めるべき設計事項
- `AppStateClient` に何を載せるか（永続設定と実行時状態の境界）
- Overlay Window 操作をどこまで DataSource 化するか（AppKit境界）
- Python bridge 呼び出し面を Repository か Client か

## 7. 初手の実装提案（次コミット候補）
1. `LocalPackage` 作成
2. `DependencyClient` / `AppDependencies` / `Composable` を最小実装
3. `VialRawHIDClient` と `HIDKeyboardClient` を追加し、既存実装を委譲
4. `AppModel` の呼び出し先を client 経由に切替（機能同等）
