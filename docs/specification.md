# 仕様書（仮）

このドキュメントは KeyMapRender の仕様管理用です。
初期版のため、章立てのみ定義しています。

## 1. 目的
- 特定キーを長押しした間だけ、キーボードレイアウトを全画面オーバーレイ表示する。

## 2. 想定ユーザー
- Vial/VIA 対応キーボード利用者
- キーマップ確認を一時的に画面上へ表示したいユーザー

## 3. 機能要件
- 指定キー（キーコード）の長押し開始を検知する
- 長押し継続中は半透明オーバーレイWindowを表示する
- キーを離したらオーバーレイを非表示にする
- 長押し対象キーと閾値秒数を設定できる
- Vial/VIA 形式 JSON（`layouts.keymap`）からレイアウトを読み込む
- 修飾キー（Shift/Ctrl/Option/Command/Fn/Caps）の長押しにも対応する
- オーバーレイは現在操作中の画面（マウスカーソルが存在するディスプレイ）中央に表示する
- Vial 対応キーボード接続時は、将来的にデバイスからキーマップを直接取得できる設計とする
- 接続キーボードを列挙し、対象デバイスを選択できる
- Vial Raw HID 通信テストにより protocol version / layer count / L0R0C0 keycode を取得できる
- matrix rows/cols 指定で dynamic keymap buffer（0x12）を全量読出しできる
- Vial `layouts.labels` / `layout_options` を読取り、物理レイアウト分岐（例: split space）を選択反映できる

## 4. 非機能要件
- macOS ネイティブアプリ（SwiftUI + AppKit）
- グローバルキー監視に必要な権限を前提とする
- キー監視中も通常入力を阻害しない（イベントは透過）
- キー監視には Accessibility に加えて Input Monitoring の許可を必要とする

## 5. 画面/操作仕様
- 設定画面（通常Window）
  - 対象キーコード入力
  - 長押し秒数スライダー
  - 設定再適用ボタン
  - 権限/監視状態表示
- オーバーレイ画面（全画面半透明Window）
  - 中央にキーボードレイアウトを表示
  - キー離上で即時非表示

## 6. データ仕様
- 設定値
  - `targetKeyCode`（Int）
  - `longPressDuration`（Double）
- レイアウト
  - `name`（String）
  - `rows`（キー配列）
  - Vial/VIA の `layouts.keymap` を解釈

## 7. 制約・前提
- アクセシビリティ権限が必要
- 入力監視（Input Monitoring）権限が必要
- Vial 直接読出しは、Vial 対応ファームを書き込んだキーボードのみ対象

## 8. 実装ステータス
- 実装済み
  - 長押し検知（通常キー + 修飾キー）
  - 半透明オーバーレイ表示（キー押下中表示、離上で非表示）
  - 画面中央表示（現在操作中ディスプレイ基準）
  - JSON（`layouts.keymap`）読み込み
  - 接続キーボード列挙（VID/PID表示）
  - Vial Raw HID 通信テスト（最小読出し）
  - 全キー行列読出し（rows/cols 手動指定）
  - LUCA移行の第一段として、DependencyClient / AppDependencies 経由の依存注入基盤を導入
  - `luca --platform macOS` 生成の `LocalPackage` 雛形（DataSource/Model/UserInterface）を導入
  - `KeyMapRender.xcodeproj` に `LocalPackage(DataSource)` を接続し、段階移行の実行経路を確立
- 未実装
  - 接続キーボードの自動識別とレイアウト自動切替
  - matrix rows/cols の自動推定

## 9. 今後の検討事項
- LUCAアーキテクチャ（DataSource / Model / UserInterface）への段階移行
- 実機の Vial JSON バリエーション対応強化
- キーコード入力を物理キー押下で学習するUI追加
- 複数レイアウト切替、ファイル選択UI追加
- Vial HID 通信レイヤーの実装（デバイス列挙、対応判定、マップ取得）

## 更新履歴
- 2026-02-23: 初版（雛形作成）
- 2026-02-23: 長押しオーバーレイ表示要件を追記
- 2026-02-23: 修飾キー対応、表示位置仕様、Vial直接読出し方針を追記
- 2026-02-23: 接続キーボード列挙とVial Raw HID最小通信テスト要件を追記
- 2026-02-23: dynamic keymap buffer読出し（rows/cols指定）を追記
- 2026-02-23: レイアウト分岐（split space 等）の選択反映要件を追記

- 2026-02-24: LUCA適合方針（段階移行）を追記

- 2026-02-24: LUCA依存注入基盤（DependencyClient / AppDependencies）を導入
- 2026-02-24: `luca --platform macOS` 生成の LocalPackage 雛形を導入
