# 0004: 用途別 CLI ヘルプと最小起動例を提供する

状態: proposal / open。実装・実行テストは未実行。
Updated: 2026-10-11
Baseline: `003e25b1113f0a252b6889f4e13f76f135d6a795` (`main`)
観測対象: macOS Apple Silicon / dsh v0.1.16 の利用者ログ

## 目的

`dsh web -h` を実行した利用者が、必要なコマンド、保存先、アクセス先をその場で判断できるようにする。全機能を読む前に、目的の画面を起動できる入口を用意する。

## 観測事実と原因

1. 利用者ログの `dsh web -h` は、run、session 操作、MCP、ACP、hook、LSP、subagent まで含む全体ヘルプを返している。
2. Usage の `--workspace PATH --data-dir PATH` は必須に見えるが、[cli_options.mbt](../../runtime/cli_options.mbt) の `native_cli_paths` には既定値がある。CLI の workspace は cwd、data-dir は `<workspace>/.dsh.mbt`。
3. [main.mbt](../../runtime/main.mbt) は引数正規化後に共通の `native_usage()` を出力する。desktop はこの分岐より先に launcher に渡されるため、desktop 専用ヘルプを同じ位置に足すだけでは足りない。
4. CLI web の既定 port は 3080。[service.mbt](../../runtime/service.mbt) は起動時に実際の URL を既に表示している。この表示自体の欠落を不具合とは扱わない。

上記はログとソースの確認結果であり、本提案作成時に実機再現はしていない。

## 実装範囲

1. 引数正規化で用途を失う前に、既知 subcommand の help 要求を識別する。最低限 `web`、`run`、`desktop`、`mcp`、`acp` を用途別ヘルプにする。
2. 全体ヘルプには用途別の短い command 一覧と各 `COMMAND --help` への導線を置く。詳細オプションは対応する用途で説明する。
3. web ヘルプの先頭に、既存 workspace で使う `dsh web` と、試験用 workspace で使う `dsh web --demo --workspace /absolute/path/to/scratch` を載せる。demo は承認付きファイル操作を試す機能もあるため、試験用保存先を説明する。
4. `[--workspace PATH]`、`[--data-dir PATH]` のように任意指定を表現し、CLI の cwd / data-dir / port と desktop の既定 workspace を区別して記載する。desktop の既定 workspace は現在 home であり、CLI と同一だと説明しない。
5. web では起動後に表示される URL をブラウザで開くこと、終了操作、API-key / ChatGPT sign-in の入口を短く案内する。認証方式の実装は変更しない。
6. ヘルプは runtime / data store を開かず、外部 MCP・hook・LSP、provider 通信、アプリ起動を行わない。`--` 以降や option value にある `-h` を help と誤認しない。

## 受入条件

- [ ] `dsh --help` / `dsh -h` は全体ヘルプ、`dsh web --help` / `dsh web -h` は web 専用ヘルプを返し、正常終了する。
- [ ] `dsh desktop --help` は Dsh.app がなくても launcher を呼ばず、正常終了する。unsupported platform でも導入条件を読める。
- [ ] web 専用ヘルプの冒頭だけで最小起動例、既定保存先、既定 port、URL を開く手順を確認できる。
- [ ] CLI / desktop の既定値は実装と一致し、明示 override の説明がある。
- [ ] help 実行前後で workspace / data-dir の内容が変わらず、provider / 外部プロセスが起動しない。
- [ ] `dsh run -- -h` のような prompt と help の意味を混同しない。
- [ ] 既存の引数順序、`--`、option value を含む正規化 regression が通る。

## 検証計画

未実行。実装 PR で [cli_options_wbtest.mbt](../../runtime/cli_options_wbtest.mbt) の parser regression と、release CLI の subprocess smoke を実施する。必要な断片・終了コード・副作用を確認し、全文 snapshot だけで合否を決めない。

## 関連と境界

- [0005: 配布・初回起動案内](0005-installation-and-first-run-guide.md) は README と配布物の説明を担当する。
- [0006: desktop エラー終了](0006-desktop-launch-recovery.md) は launcher の失敗を通常終了にする。
- 全体ヘルプの改善は既存機能の入口を整理する作業であり、provider、権限、データ形式の変更は対象外。
