# 0001: DeepSeek Harness の残りの機能を MoonBit へ移植する

状態: open。最初の browser / CLI 実行経路は [移植状況](../../docs/port-status.md) を参照。
upstream baseline は `5badb15009ae1756c3afe0ae0cef1faafc290ccc`。

## 1. Session v4 と replay

upstream JSONL を version ごとに厳密に decode し、イベントの意味を MoonBit 型へ移す。
未知の event、attachment、interruption を黙って捨てない。v4 のまま保存するか、明示的な importer として独自 schema へ移すかを仕様に記録する。

受入条件:

- upstream の snapshot fixture を変更せずに読み、user / assistant / tool と相関情報を再構築する。
- branch / fork、inbox、複数 turn、failed / cancelled / interrupted の fixture を追加する。
- import と reopen で外部作用が発生しない。
- 現在の `dsh.mbt-session-v1` 履歴も明示的な migration で読み続けられる。

## 2. 長い会話と stream projection

compaction、tool result pruning、spill を導入し、262,144-unit 上限に依存しない長い会話を支える。
provider SSE の delta を engine event と UI に逐次反映し、切断時の未完了 tool を実行しない。

受入条件:

- 旧上限を超える複数 turn の会話が継続し、縮約前後の履歴が説明可能である。
- arbitrary chunk / Unicode / EOF / cancel の途中状態を再現する。
- retry の回数、理由、重複実行防止を durable event として追跡する。

## 3. 拡張機能と tool 統合

MoonBit の typed service / lifetime を定義して、startup metadata から動的な拡張境界へ進める。
external MCP client、ACP、hooks、LSP、skills、subagent の順に相関と終了条件を仕様化する。
Cordis / npm plugin をそのまま動かす場合は別の互換 host を設計し、MoonBit-only plugin とは区別する。

受入条件:

- plugin mount / teardown 中の依存、保有リソース、tool 呼出しを一貫して扱う。
- 子 agent / process / external tool を親の cancel で停止し、再開時に重複実行しない。
- 各拡張に成功・拒否・timeout・切断・reopen の結合テストを追加する。

## 4. Provider と UI の機能範囲

画像 / file、thinking signature の保存と replay、mid-conversation system / tool update、model discovery を追加する。
gpui を使って settings、attachment preview、workspace change、terminal / subagent 表示へ広げる。
native window は browser と共有できる state / scene を保って別の host adapter として実装する。

受入条件:

- 保存して再読込した request を provider が受理でき、失われる metadata を明示する。
- 実 API 検証は認証をログへ残さず、keyless fixture の検証と区別して記録する。
- native target で window、入力、IME、resize、close の実機検証を完了する。

## 5. Host と運用

OS sandbox、persistent terminal、SSH workspace、job / schedule、認証付き remote API を独立した host capability として追加する。
現在の loopback / local workspace の挙動を維持し、利用者が有効化した機能だけを公開する。

受入条件:

- 対応 OS ごとの filesystem / process 権限と recovery を検証する。
- remote API には authentication / authorization と複数利用者の分離を導入する。
- 新しい production package を mutation gate に追加し、単なる mutant 列挙を成功扱いしない。

## gpui-mbt 依存の追跡

`hotpath.mbt` の固定 revision は standalone LICENSE / manifest license field を含まない。
dependency の license metadata が upstream に追加されたら確認し、pin と第三者通知を更新する。
この repository の MIT 表記を依存ソースに転用しない。
