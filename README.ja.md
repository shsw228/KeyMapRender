# KeyMapRender

[English README](README.md)

KeyMapRender は、設定したキーの押下中（またはトグル時）に、Vial/VIA 対応キーボードのレイアウトを半透明オーバーレイで表示する macOS アプリです。

## 主な機能
- 対象キーの設定によるオーバーレイ表示/非表示
- 接続キーボードからの Vial キーマップ読出し（Raw HID / Python bridge）
- レイヤ追従表示とキーラベル描画
- `layouts.labels` / `layout_options` に基づく物理レイアウト分岐選択
- `vial.json` エクスポート、診断ログ確認、権限状態表示

## 必要条件
- macOS（Xcode ビルド環境）
- Accessibility 権限
- Input Monitoring 権限

## ビルド
1. `KeyMapRender.xcodeproj` を Xcode で開く
2. `KeyMapRender` ターゲットをビルド・実行する
3. 必要に応じて `システム設定 > プライバシーとセキュリティ` で権限を許可する

## 動作確認端末（現行）
- Agar mini

## 関連ドキュメント
- 仕様書: `docs/specification.md`
- LUCA移行計画: `docs/luca_migration_plan.md`

## ライセンス
- このリポジトリは **GNU General Public License v3.0 (GPL-3.0)** でライセンスされています。
- 詳細は `LICENSE` を参照してください。
- サードパーティライセンスはアプリメニュー（`Third-Party Licenses…`）で確認できます。
- 同梱ライセンスファイル:
  - `KeyMapRender/Resources/python_deps/hidapi-0.15.0.dist-info/licenses/`
