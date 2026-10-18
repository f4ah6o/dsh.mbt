# 0006: desktop の未導入・起動失敗を通常のエラー終了として扱う

状態: proposal / open。実装・実行テストは未実行。
Updated: 2026-10-11
Baseline: `003e25b1113f0a252b6889f4e13f76f135d6a795` (`main`)
観測対象: macOS Apple Silicon / dsh v0.1.16

## 目的

Dsh.app がないだけで CLI が abort しないようにする。利用者が失敗の場所・理由・次の操作を理解でき、スクリプトも通常の終了コードで扱える状態にする。

## 再現と原因

利用者ログ:

```text
$ dsh desktop
Dsh.app was not found in /Applications or ~/Applications; install it there or pass --app-path /absolute/path/to/Dsh.app
zsh: abort      dsh desktop
```

[desktop_launch.mbt](../../runtime/desktop_launch.mbt) は bundle 不在、引数不正、LaunchServices 失敗を `Result` の `Err` として返す。[main.mbt](../../runtime/main.mbt) の desktop 分岐が `Err(error) => abort(error)` として扱っていることをソースで確認した。未導入を想定外のプロセス異常に変換している箇所がここにある。

ログの abort 表示は確認済み。本提案作成時には実機で signal / core dump の有無を測定していない。

## 実装範囲

1. desktop launcher の想定内エラーを CLI 境界で整形し、stderr に出力して通常の非ゼロ終了にする。`abort` を使わない。
2. この increment では終了コードを成功 0、起動 / 環境エラー 1、引数不正 2 として区別する。詳細は内部 source location を露出せず、失敗した操作と対象を示す。
3. bundle 不在では別配布の `Dsh-macos-arm64.zip`、release guide、`/Applications` / `~/Applications`、任意配置の `--app-path` を提示する。
4. 明示 `--app-path` が不完全な bundle を指す場合は、その指定先を問題として説明し、別アプリを探して黙って起動しない。
5. 非 macOS、`/usr/bin/open` 起動失敗、LaunchServices 非ゼロ終了をそれぞれ表示する。OS の拒否理由が得られなければ、未署名・権限などの原因を断定しない。
6. 正常時は既存の引数配列による forwarding と LaunchServices 経由起動を維持する。起動後のアプリ終了を CLI 起動成功と混同して監視する機能は追加しない。

## 受入条件

- [ ] Dsh.app がないとき、短い stderr と通常の終了コード 1 を返す。SIGABRT / signal 終了を使わず、成功表示を出さない。
- [ ] `--app-path` の欠落値・重複・相対パス等は終了コード 2 と修正例を返す。
- [ ] 不完全な明示 bundle では、指定先と必要な配布物を示して終了コード 1 を返す。
- [ ] 非 macOS / LaunchServices failure は場所・観測できた理由・対処を表示し、通常終了する。
- [ ] stdout は失敗時の診断で汚れず、同じエラーを重複表示しない。
- [ ] 正常な bundle の起動と、空白・日本語・`--` を含む引数 forwarding が regression しない。
- [ ] 0004 適用後の `dsh desktop -h` は bundle 不在でも終了コード 0 で、実際の launcher は呼ばれない。

## 検証計画

未実行。[desktop_launch_wbtest.mbt](../../runtime/desktop_launch_wbtest.mbt) の既存 parser / bundle selection / argv tests に加え、CLI 子プロセスの return code と stderr / stdout を検査する。fixture の一時 HOME を使い、system-wide bundle がある CI でも未導入条件を決定的に再現する。実装時に lookup / LaunchServices capability の fixture 境界を用意し、実際の /Applications の削除で条件を作らない。macOS release smoke で正常起動も別に確認する。

## 関連と境界

- [0004: 用途別ヘルプ](0004-task-oriented-cli-help.md) は help の早期処理を担当する。
- [0005: 配布・初回起動案内](0005-installation-and-first-run-guide.md) は download / 配置説明を担当する。
- ACP の stdout contract、worker fatal path、他の全 `abort` の一括変更、Dsh.app 自動導入は対象外。まず利用者ログにある desktop failure を独立して修正する。
