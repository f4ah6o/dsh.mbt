# 移植状況

基準は [DeepSeek Harness `5badb15009ae1756c3afe0ae0cef1faafc290ccc`](https://github.com/deepseek-ai/deepseek-harness/tree/5badb15009ae1756c3afe0ae0cef1faafc290ccc)
（`0.2.1-alpha.1`）です。upstream 全体の TypeScript package を機械的に置換した版ではなく、
MoonBit で agent の基本実行経路を動かす最初の移植です。

**実装済み**はこの表に記載した範囲を動作させるコードとテストがあることを示します。
同じ行に対応する upstream package の全機能互換を意味しません。

| upstream の領域 | 移植先 | 状態と差分 |
| --- | --- | --- |
| `core/session`, `core/agent-loop`, `core/tools` | `engine/` | 基本 turn / step、event log、messages、直列 tool、follow-up、cancel、late result 拒否を実装済み。inbox 編集、branch / fork、parallel tool は未実装。 |
| `interaction/user-approval` | `engine/`, `api/`, `web/`, `host/cli.mjs` | read / write / shell 分類、呼出しごとの Allow / Deny、明示的 startup 自動承認を実装済み。upstream permission preset / account authorization の互換は未実装。 |
| `llm/llm-deepseek` | `provider/`, `host/provider.mjs` | Messages / Chat Completions の text、reasoning、function tool、usage、JSON / incremental SSE を実装済み。画像、Files API、model discovery、thinking signature の durable replay は未実装。 |
| `session/session-persistence*`, `session/session-projection` | `engine/`, `host/persistence.mjs` | 検証付き復元、atomic snapshot、interruption の終了、no replay を実装済み。保存形式は独自 `dsh.mbt-session-v1`。upstream v0–v4 migrations / JSONL 互換は未実装。 |
| `fs/tool-fs*`, `fs/tool-str-replace-editor` | `plugins/`, `host/tools.mjs` | read / write / edit / glob / grep を実装済み。workspace 制限、symlink 拒否、bounded regex / output。SSH filesystem、filesystem observation は未実装。 |
| `shell`, `subprocess` | `host/tools.mjs` | opt-in bash、timeout / cancel、出力上限を実装済み。persistent shell、terminal、PowerShell、OS sandbox は未実装。 |
| `client/ui-*`, `client/web` | `ui/`, `web/` | gpui scene による transcript、承認、会話一覧、再接続、scroll、Text view、mobile を実装済み。upstream の全設定画面 / sidebar / attachment preview は未実装。 |
| `api`, `sdk/protocol`, `typert` | `api/`, `app/`, `host/server.mjs` | gpui typed capability / GUI binding / MCP で置換。upstream API / SDK wire compatibility は提供しない。 |
| `boot/plugin-manager`, `extensions/cordis-*` | `plugins/` | MoonBit startup descriptor の依存・重複・tool 所有権を実装済み。npm / Cordis ABI、runtime code loading、HMR は未実装。 |
| `session/session-telemetry*`, inspector | `api/` + hotpath | API 呼出し時間の集計を実装済み。OpenTelemetry、CPU / allocation sampling は未実装。 |
| `test-support/session-snapshot`, `test-support/llm-replay` | `tests/fixtures/`, `tests/integration/` | upstream tool-call-turn fixture の provenance を保持し、実 tool と完了応答を再現。全 snapshot catalog の importer / replay は未実装。 |
| `compaction`, `spill`, `attachment`, `context` | — | 未実装。初期版は明示的な容量上限で閉じる。 |
| `subagent`, `goal`, `plan`, `workflow`, `jobs`, `schedule`, `todo` | — | 未実装。 |
| 外部 MCP client / ACP / hooks / LSP / skill loader | — | 未実装。gpui MCP server の公開とは別機能。 |
| browser / computer use、SSH、account login、web search、office preview | — | 未実装。 |

## 意図的な初期版の選択

- JavaScript output を Node host と browser の双方で使う。portable package の native テストは native GUI の完成を意味しない。
- 依存を upstream Git revision に固定し、互換性が確認できていない latest へ自動更新しない。
- SSE は MoonBit で逐次解析する。session / UI の streaming delta 更新は後続作業とする。
- 自動 HTTP retry は行わない。新しい外部作用を再試行する policy と durable recording は後続作業とする。
- 1 session 262,144 serialized UTF-16 units、最大 32 sessions。容量超過を明示し、履歴・承認・再開の整合性を保つ。
- browser host は loopback 専用。認証付き remote service や deployment platform はこの版に含めない。

## 完了済みの最初の受入経路

1. recursive checkout と固定 compiler / core から build できる。
2. API key なしの demo で browser / CLI から実際の workspace tool turn が完了する。
3. DeepSeek Messages / OpenAI Chat Completions を mock transport で実行できる。
4. approval 前の write は実行されず、Allow の記録後にだけ実行する。Deny / cancel も履歴に残る。
5. 保存して閉じ、再度開いても completed message を保持する。interrupted effect を自動再実行しない。
6. upstream の `echo SNAPSHOT_OK` → tool result → `DONE` の実記録を抽出 fixture で再現する。
7. gpui UI / capability API、hotpath 計測、turtles mutation gate を実際のアプリ経路で使う。

追加の受入条件は [次の移植作業](../issues/open/0001-upstream-parity.md) に追跡します。
live provider への有料 API 呼出しと macOS native window の実機試験はまだ行っていません。
