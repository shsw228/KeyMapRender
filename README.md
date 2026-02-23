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

## ドキュメント
- 仕様書: `docs/specification.md`
