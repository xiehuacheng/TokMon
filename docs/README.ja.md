[中文](../README.md) | [English](./README.en.md) | **日本語**

# TokMon

> macOS メニューバー型の Token 使用統計アプリ

![GitHub top language](https://img.shields.io/github/languages/top/xiehuacheng/tokmon) ![GitHub Repo stars](https://img.shields.io/github/stars/xiehuacheng/tokmon?style=social) ![GitHub forks](https://img.shields.io/github/forks/xiehuacheng/tokmon?style=social) ![GitHub License](https://img.shields.io/github/license/xiehuacheng/tokmon) ![GitHub Issues](https://img.shields.io/github/issues/xiehuacheng/tokmon) ![GitHub last commit](https://img.shields.io/github/last-commit/xiehuacheng/tokmon)

## 目次

- [画面プレビュー](#画面プレビュー)
- [機能概要](#機能概要)
- [システム要件](#システム要件)
- [インストールとダウンロード](#インストールとダウンロード)
- [クイックスタート](#クイックスタート)
- [画面の説明](#画面の説明)
- [対応データソース](#対応データソース)
- [設定とデータ](#設定とデータ)
- [プロジェクト構成](#プロジェクト構成)
- [ドキュメント](#ドキュメント)
- [ライセンス](#ライセンス)

## 画面プレビュー

<p>
  <img src="docs/images/tokmon-popover-light.png" alt="TokMon のライトモードでの macOS メニューバー Popover" width="320">
  <img src="docs/images/tokmon-popover-dark.png" alt="TokMon のダークモードでの macOS メニューバー Popover" width="320">
</p>

メニューバーアイコンをクリックすると、リアルタイム統計の確認、パネル画像のコピー、設定ウィンドウの表示、アプリの終了などが行えます。

## 機能概要

- **複数ソースの統合**：Claude Code、Codex、Kimi Code、Qwen Code、OpenCode のローカルログ/データベースを自動スキャンします。
- **指標の切り替え**：Total Tokens、Requests、Input Tokens、Output Tokens、Cache Created、Cache Hit、Hit Rate、Est. Cost を切り替えて表示できます。
- **時間範囲**：Today / This Week / This Month / All / Custom のショートカット範囲に対応しています。Custom は Popover 内で直接開始日と終了日を選択できます。
- **トレンドとヒートマップ**：トレンドグラフ、ソース/モデル別の内訳、コンパクトなアクティビティヒートマップに対応しています。命中率などの割合系指標は、データ分布に応じて縦軸を動的に調整し、変動幅と識別性を両立します。
- **リクエストと Session**：リクエストログのページング表示、session 詳細の両方でキーワード検索による絞り込みが可能です。session タイトルは、session 名/プロジェクトフォルダ名と最初の prompt を優先して使用します。
- **Kimi Quota**：複数 API Key の管理、週間 Quota と 5 時間ローリング Quota の表示、手動または定時更新に対応しています。API Key が未設定の場合、Quota カード/タブは表示されません。
- **メニューバー表示**：設定から、メニューバーに Total Tokens、Est. Cost、Requests、Cache Hit Rate、Kimi Weekly Quota、Kimi 5-Hour Quota を表示できます。
- **料金見積もり**：モデルごとに料金を設定するか、グローバルなデフォルトレートを使用して Est. Cost を見積もることができます。
- **外観の適応**：ライト/ダークモードに対応し、アクセントカラー、メニューバーアイコン、テキストがシステム外観に自動で追随します。
- **スクリーンショット共有**：Popover 右上のカメラアイコンをクリックすると、現在のパネルを画像としてコピーできます。初回使用時に画面収録の許可を求められます。
- **自動更新**：Sparkle を内蔵しており、GitHub Release の更新を手動または自動で確認できます。

## システム要件

- macOS 14 以降

## インストールとダウンロード

1. [GitHub Releases](https://github.com/xiehuacheng/TokMon/releases) から最新の `TokMon-X.Y.Z.dmg` をダウンロードしてください。
2. DMG を開き、`TokMon.app` を **Applications** にドラッグしてください。
3. 初回起動時、macOS の Gatekeeper 警告が表示されることがあります。現バージョンはローカルな ad-hoc 署名を使用しており、Apple の公証は受けていないため、システムの指示に従って対応してください。
4. 起動後、メニューバーの TokMon アイコンをクリックして使用を開始してください。

詳細な使用方法、ビルドと開発の手順については、[`macos-app/README.md`](macos-app/README.md) を参照してください。

## クイックスタート

**開発環境での実行**（Xcode / Swift 6.0 ツールチェーンが必要）：

```bash
cd macos-app
swift run TokMon
```

**スタンドアローン `.app` のビルド**：

```bash
bash macos-app/scripts/build-app.sh
open macos-app/release/TokMon.app
```

ビルド成果物は `macos-app/release/` に出力され、`.gitignore` で無視されているため Git には含まれません。

## 画面の説明

### メニューバー Popover

Popover は 4 つのタブで構成されています。

- **Tokens**：コア指標カード、トレンドグラフ、アクティビティヒートマップ、ソース/モデル別の内訳。
- **Requests**：リクエストログのページング表示。各リクエストの tokens、モデル、session、時刻などの詳細を表示し、検索による絞り込みに対応しています。
- **Sessions**：session 単位で集計した統計リスト。検索による絞り込みに対応しています。
- **Quota**：Kimi API Key の Quota パネル。key の追加、削除、リネーム、切り替えに対応しています。未設定時は非表示になります。

右上のツールバーボタンは、順に更新、画像としてコピー、設定を開く、更新を確認、アプリを終了です。

### 設定ウィンドウ

設定ウィンドウは以下のセクションで構成されています。

- **General**：起動時に自動で起動するかどうかを設定します（Launch at Login）。
- **Sources**：Popover に表示するデータソースを複数選択できます（Select All + 各ソースの個別トグル）。各 agent のローカルデータパスも設定できます。
- **Menu Bar**：メニューバーに表示する指標項目を選択します。
- **Model Pricing**：モデルごとに input/output/キャッシュ作成/キャッシュ読み取りの単価を設定し、料金見積もりに使用します。
- **Kimi Quota**：Kimi Quota パネルの自動更新間隔を設定します（デフォルト 5 分、Manual / 1 / 5 / 15 / 60 分から選択）。
- **Maintenance**：手動で **Rebuild Database** を実行します。即時更新ボタンは Popover のツールバーにあります。

## 対応データソース

TokMon はデフォルトで以下のパスを読み取ります。すべてのパスは設定ウィンドウの **Sources** セクションで変更できます。

| データソース | デフォルトパス | 説明 |
| --- | --- | --- |
| Claude Code | `~/.claude/projects` | ローカルの session ログをスキャン |
| Codex | `~/.codex` | `sessions/`、`archived_sessions/` 配下の `.jsonl` と `.jsonl.zst` ファイルを再帰スキャン |
| Kimi Code | `~/.kimi-code` | `agents` ディレクトリを含む `wire.jsonl` ログを再帰的に検索 |
| Qwen Code | `~/.qwen/projects` | ローカルのプロジェクトログをスキャン |
| OpenCode | `~/.local/share/opencode` | このディレクトリ内の `opencode.db` SQLite データベースを読み取り |

## 設定とデータ

TokMon はゼロ設定で動作します。`.app` から起動した場合、SQLite データベース、スキャン状態、ローカル設定は以下に書き込まれます。

```text
~/Library/Application Support/TokMon
```

このディレクトリ内の主なファイル：

- `tokmon.db`：SQLite データベース
- `tokmon.config.json`：ソースパスなどのアプリ設定
- `tokmon-ui-state.json`：UI 状態（範囲、指標、メニューバー表示項目、モデル価格など）
- `tokmon-kimi-keys.json`：Kimi API Key 一覧
- `tokmon-kimi-quota-<id>.json`：各 key の Quota キャッシュ

### AgentMon からの移行

初回起動時、`~/Library/Application Support/TokMon` が存在せず、旧版の `~/Library/Application Support/AgentMon` が存在する場合、TokMon は自動的にデータディレクトリを移行し、`agentmon.db*` を `tokmon.db*` にリネームします。TokMon ディレクトリがすでに存在する場合は上書きしません。

### スキャンバージョンとデータベースの再構築

`TokMonScanner.scannerVersion` は現在 `5` です。スキャンやマージのセマンティクスが変わると、このバージョン番号は増加します。アプリ起動時にローカルに保存されているバージョンが現在のバージョンより低い場合、自動的にデータベースを再構築し、すべてのデータを再スキャンします。

### データの一貫性

- 使用量レコードは `usage_records` テーブルに書き込まれ、増分スキャンの offset は `tokmon_scan_state` テーブルに書き込まれます。
- Claude Code の assistant レコードには `message_id` が含まれており、同一 `message.id` に対する複数の streaming chunk の重複排除に使用されます。`createdAt` が最も新しいものを保持し、同じ場合は total tokens がより大きいものを保持します。
- キャッシュヒット率（Hit Rate）の分母/分子は、`cacheHitSupported` が true のレコードのみを集計します。現在、すべての組み込みソースはデフォルトで対応しており、将来このセマンティクスに対応しないデータソースが追加されてもヒット率が薄まることはありません。

## プロジェクト構成

```text
macos-app/
  Package.swift          # SwiftPM マニフェスト（macOS 14+、Sparkle 依存）
  Sources/TokMonApp/     # SwiftUI / AppKit メニューバーアプリのソース
  Tests/TokMonAppTests/  # Swift テスト
  Assets/                # アプリアイコン
  Packaging/Info.plist   # .app bundle メタデータ
  scripts/build-app.sh   # スタンドアローン .app ビルドスクリプト
  scripts/build-dmg.sh   # 署名付き DMG と Sparkle appcast.xml 生成スクリプト
  README.md              # アプリの使用、ビルド、開発の説明
docs/
  images/                # README スクリーンショット
```

ルートディレクトリにはさらに、`AGENTS.md`（汎用 agent 協約）、`CLAUDE.md`（Claude Code 協約）、`LICENSE` が含まれます。

## ドキュメント

- [`README.md`](README.md)（本ファイル）：プロジェクトの概要、機能紹介、インストールとクイックスタート。
- [`macos-app/README.md`](macos-app/README.md)：スタンドアローンアプリの詳細な使用、開発、ビルド、リリース手順。
- [`AGENTS.md`](AGENTS.md)：本リポジトリに入るすべての AI agent 向けの汎用協約。
- [`CLAUDE.md`](CLAUDE.md)：Claude Code 専用の使用説明。

## ライセンス

[MIT](LICENSE)

> この文書は翻訳版です。正確な内容は README.md を参照してください。
