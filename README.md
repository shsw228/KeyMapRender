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

## ドキュメント
- 仕様書: `docs/specification.md`
