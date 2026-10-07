# 検証記録

## iOS client lifecycle fencing increment

2026-10-07、macOS arm64、Xcode 26.6 / iOS Simulator SDK 26.5、Node.js
`24.21.0`、MoonBit compiler `0.10.14+7d59c7ec9` で選択 gate を実行しました。

| command | 結果 |
| --- | --- |
| `sh ios/ClientEmbedding/test-model.sh` | PASS。13 scenarios。遅延 snapshot / session / POST / receipt / SSE response、suspend 中の deferred reconnect、host switch / identity-scope snapshot injection / selection intent、uncertain ID no-replay、user-scroll `follow_latest` policy を確認。SSE body 自体は fixture stream から注入していません。 |
| `sh ios/ClientEmbedding/verify-abi.sh` | PASS。MoonBit C ABI lifecycle と UTF-8 smoke。 |
| `npm run check` | PASS。MoonBit all-target checks、app JS check、JavaScript syntax 35 files、自身の warning 0。固定 hotpath deprecation diagnostics のみ。 |
| `xcodebuild -project ios/ClientEmbedding/DshClientEmbedding.xcodeproj -scheme DshClientEmbedding -sdk iphonesimulator26.5 -derivedDataPath _build/ios-client-derived build` | PASS。arm64 / x86_64 Simulator app build。Generic destination resolution was unavailable because the active Xcode had no matching installed runtime; selecting the installed Simulator SDK built successfully. |

The URLProtocol host is synthetic and deterministic. This run did not install or launch a Simulator, contact a live dsh host, sign into ChatGPT, use Tailscale Serve, or test a physical iPhone. Those remain separate acceptance gates.

2026-10-06、macOS arm64、Node.js `24.21.0`、MoonBit compiler / core
`0.10.14+7d59c7ec9`、固定 moon / moonrun で実行。
以下は実行して終了を確認した local の結果です。GitHub Actions の状態は対象 PR の Checks を参照してください。

## 前回の通常 gate

次の表は Session v4 parity increment より前の baseline 実行記録です。現在の変更に対する選択 gate は下の
「Session v4 parity increment」に記録しています。最終 PR gate は変更を取り込んだ状態で再実行します。

`npm test` **PASS / exit 0**。

| 対象 | 結果 |
| --- | --- |
| 固定 toolchain / core / 3 submodule の確認 | PASS |
| MoonBit format と check | PASS。自身の warning 0 |
| JavaScript source / test の syntax check | PASS、25 files |
| MoonBit portable packages / JS | 56 / 56 PASS |
| MoonBit portable packages / native | 56 / 56 PASS |
| MoonBit portable packages / Wasm | 56 / 56 PASS |
| MoonBit portable packages / Wasm GC | 56 / 56 PASS |
| JavaScript app release build | PASS |
| Node host | 34 / 34 PASS |
| Browser view model | 8 / 8 PASS |
| Built app integration | 8 / 8 PASS |

`app` 自体に MoonBit unit test はなく、生成 ESM の export / lifetime は Node 結合テストで検証しています。
固定 hotpath source の `derive(Show, Eq)` に由来する 3 種の warning は依存の既知診断として表示します。
自身の warning、別の依存からの warning、format 差分は check を失敗させます。

## Session v4 parity increment

2026-10-06 の現在の変更に対して、以下の repository-selected gate を実行しました。

| command | 結果 |
| --- | --- |
| `npm run check` | PASS。MoonBit format、engine/provider/plugins/api/ui の all-target check と app JS check、自身の warning 0、JavaScript syntax 25 files。pinned hotpath warning のみ。 |
| `npm run test:moon` | engine/provider/plugins/api/ui は Wasm、Wasm GC、JS、native の各 target で 57 / 57 PASS。app JS target は test entry なし。 |
| `npm run build` | PASS。`_build/js/release/build/f4ah6o/dsh/app/app.js` を生成。 |
| `npm run test:integration` | 17 / 17 PASS。Session v4 importer の選択ケースは 15 / 15 PASS。 |

この変更で追加した MoonBit white-box coverage は、数値の前後と異なる current-position の replacement、
逆向き / 不在 surface boundary の拒否、tool result の identity・座標保持を確認します。Node integration は、
unmodified upstream fixture の import / reopen、provider・tool effect が 0 件、tampered relationship の atomic rejection、
assistant を引用する surface replacement、過去 turn の tool-result pruning、between-step checkpoint、
standalone `turn: null` compaction、summary / prune 後の first-level fork cut を確認します。
さらに、空文字の text block は empty message として表示し、空 content array は derived message だけを省き、
surface node 自体は後続 replacement で参照できることを確認します。

restore は、旧 append-only importer subset が受理した archive について、過去の v1 message projection と完全一致する
snapshot も認識し、現在の canonical projection へ移行します。raw source lines、event coordinates、pending-state checks は
引き続き検証します。回帰テストは legacy snapshot の restore / close / reopen と effect が発生しないことを確認し、
content、message identity、source sequence の改変や旧・新 row の混在を atomic に拒否します。

コミット済み integration catalog に追加した 5 snapshot は、pinned upstream JSONL と SHA-256 が一致することを毎回検証します。
これは full snapshot catalog test ではありません。別途、独立した release-app smoke は pinned upstream の 25 snapshot 全件を import / reopen
し、17 件を受理、8 件を未対応 semantics として拒否し、両段階で provider / tool effect が 0 件であることを確認しました。
拒否対象は `advanced-toolchain`、`advanced-toolchain-runtime`、`claude-code-mods`、`multimodal-spill-ends`、
`office-skills`、`office-skills-no-renderer`、`skill-load`、`windows-acl-skill` です。

## Session v4 catalog completion increment

2026-10-07、今回の差分を含む状態で `npm test` **PASS / exit 0**。

| command | 結果 |
| --- | --- |
| 固定 toolchain / core / 3 submodule の確認 | PASS。Node.js `24.21.0`、MoonBit `0.10.14+7d59c7ec9`。 |
| MoonBit format / package checks、JavaScript syntax | PASS。engine/provider/plugins/api/ui は all-target check、app JS check、syntax 25 files、自身の warning 0。固定 hotpath diagnostics のみ。 |
| MoonBit portable packages | Wasm、Wasm GC、JS、native の各 target で 58 / 58 PASS。app JS target は test entry なし。 |
| JavaScript app release build | PASS。 |
| Node host / browser view model | 34 / 34 PASS、8 / 8 PASS。 |
| Built app integration | 19 / 19 PASS。catalog regression は upstream Session v4 snapshot 25 件すべてを import / reopen。 |

追加した integration は unresolved image placeholder、skill catalog source、Claude Code mod append、PTC / workflow lifecycle の
correlation を確認し、画像形式・metadata、admitted user message identity/content、PTC root/parent drain order、workflow owner/name/
foreground enclosure、unsupported background flag と ignorable unknown execution-family row の偽造を atomic rejection します。
catalog import / reopen では provider / tool effect は 0 件です。全 repository gate はこの変更を含めて完了しました。

## live stream projection increment

2026-10-07、provider の live text / reasoning projection を追加した状態で `npm test` **PASS / exit 0**。
固定 session snapshot `dsh.mbt-session-v1` と read-only Session v4 importer の互換性は維持しています。
provider は complete SSE frame のみを投影し、host は bounded batch を checkpoint します。partial は次の provider context
には入らず、正常完了時だけ final message が同じ turn / step の provisional row を置き換えます。

| gate | 結果 |
| --- | --- |
| MoonBit format / checks, JavaScript syntax | PASS。自身の warning 0、pinned hotpath diagnostics のみ、syntax 26 files。 |
| MoonBit portable packages | Wasm、Wasm GC、JS、native の各 target で 68 / 68 PASS。app JS target に test entry はありません。 |
| JavaScript app release build | PASS。 |
| Node host / browser view model | 35 / 35 PASS、9 / 9 PASS。 |
| Built app integration | 32 / 32 PASS。 |

`tests/integration/live-stream.test.mjs` は実際の compiled app facade と host を使い、EOF 前の visible text / reasoning と
checkpoint、split UTF-8 と 4096-unit scalar-safe batching、truncated tool-call safety と reopen、cancel 後の late-delta fencing
と次 request の context exclusion、reader cleanup を待つ shutdown、malformed cancel 中に到着する frame の保持、
queued timer flush と cancellation の順序、5000-unit callback を drain する accepted / rejected cancellation、
cancellation より先に queue 済みの 600-unit callback の bounded completion、rejected cancel の dispatch 前 gap で届く
frame の保持、first checkpoint 中の shutdown と 5000-unit 全体の drain、70 Ki-unit callback splitting 中の shutdown、
live/durable snapshot parity を確認します。
host callback は callback 側で checkpoint を待たず、cancellation の serialized preflight が pending segments と active
checkpoint を drain するため、callback が cancellation の後ろに queue 済み flush を待つ deadlock を作りません。
shutdown は callback の新規登録を fence しつつ、登録済み delta task の scalar-safe splitting と queue drain を完了してから
final snapshot を保存するため、checkpoint 中に開始された shutdown も受理済み text を切り捨てません。
provider / engine / persistence tests は malformed/final divergence,
event identity and replay validation, capacity refusal, legacy v1 restore を検証します。

## Durable provider retry increment

2026-10-07、durable retry lifecycle を追加した差分で `npm test` **PASS / exit 0**。
すべての provider regression は keyless fixture で実行し、実 API request は行っていません。

| gate | 結果 |
| --- | --- |
| `npm run check` | PASS。MoonBit format / all-target check、自身の warning 0、JavaScript syntax 27 files。固定 hotpath diagnostics のみ。 |
| `npm run test:moon` | Wasm、Wasm GC、JS、native それぞれ 74 / 74 PASS。 |
| `npm run build` | PASS。compiled MoonBit ESM を生成。 |
| `npm run test:host` | 38 / 38 PASS。 |
| `npm run test:web` | 9 / 9 PASS。 |
| `npm run test:integration` | 41 / 41 PASS。 |
| `npm run mutation` | PASS。plugins production gate は viable 27 / 27 mutants killed、score 100%。 |

`tests/integration/provider-retry.test.mjs` は schedule と start の checkpoint が次の provider I/O より先に保存されること、
retry 時の frozen body 同一性、過去に完了した tool を再実行しないこと、queued partial delta が retry を止めること、
backoff cancel と reopen の no-replay、start checkpoint 中の shutdown、checkpoint failure 後に provider I/O が始まらないこと、
retry marker の容量拒否後も host / restore が使えること、大きすぎる numeric/date `Retry-After` の安全な拒否、
実 HTTP redirect / blocked-port failure の非 retry 分類を確認します。Host provider tests は delayed response cleanup 中に
AUTH、malformed SSE、response size-limit failure が TIMEOUT に上書きされないことを確認します。MoonBit retry tests は
retry budget、step 内での policy 固定、schedule/start identity、pending wait 中の stream delta 拒否、start marker を欠く forged
replay の atomic rejection を確認します。

## Session v4 provider retry import increment

2026-10-07、native v4 retry lifecycle import を追加した状態で `npm test` **PASS / exit 0**。
専用 retry wbtest も portable MoonBit の全 target で実行しています。retry archive は read-only history として保持し、
restore は source row と derived projection を再検証しますが provider / tool effect は発生しません。

| gate | 結果 |
| --- | --- |
| `npm run check` | PASS。engine/provider/plugins/api/ui all-target checks、app JS check、JavaScript syntax 27 files、自身の warning 0。固定 hotpath diagnostics のみ。 |
| `npm run test:moon` | Wasm、Wasm GC、JS、native 各 target 75 / 75 PASS。app JS test entry なし。 |
| `npm run build` | PASS。 |
| `npm run test:host` | 38 / 38 PASS。 |
| `npm run test:web` | 9 / 9 PASS。 |
| `npm run test:integration` | 43 / 43 PASS。 |

Native JSONL と shorthand の derived fixtures は個別 provenance 付きで追加し、unmodified upstream 25-snapshot catalog から分離しています。
Integration は完了・terminal・interrupted schedule、assistant-less `step/end` 後に続く valid schedule/start、started と未 started attempt、
fractional / 10 秒超 delay、failure / policy raw metadata、restore integrity、invalid schema / correlation の atomic rejection を検証します。
Mutation gate の対象は `plugins/plugins.mbt` のみで、
この increment は `engine/session_v4_retry.mbt` を変更するため該当 scope 外として実行していません。

## upstream の実記録を使う結合テスト

`tests/fixtures/upstream-tool-call-turn.json` は upstream の
`snapshots/session/tool-call-turn/session.v4.jsonl` から prompt と 2 回の assistant completion を抽出したものです。
`tests/fixtures/upstream-tool-call-turn/session.v4.jsonl` は元の v4 snapshot file であり、内容を変更せず保存しています。
元 repository、revision、path、SHA-256、license は fixture provenance に記録しています。

`tests/integration/upstream-replay.test.mjs` は生成済み MoonBit ESM と実際の host を使用して、次を確認します。

1. ローカル HTTP server が DeepSeek Messages request の path / headers / body を受け取る。
2. upstream 記録にある bash tool call を MoonBit engine が承認待ちとして扱う。
3. 明示的に承認された `echo SNAPSHOT_OK` が一時 workspace で実行される。
4. 実際の出力 `SNAPSHOT_OK\n` が次の Messages request に含まれる。
5. upstream 記録の最終応答 `DONE` で会話が完了する。
6. host を閉じて開き直しても同じ messages を保持し、provider / bash を再実行しない。

この runtime replay は provider と承認済み tool を動かすテストです。対して
`tests/integration/session-v4-import.test.mjs` は Session v4 の明示的 read-only importer を使い、
元 fixture の transcript projection、provider/tool effect がないこと、reopen 時の再検証、偽造 projection の
atomic rejection を確認します。生成した physical envelope のログでは multi-turn tool correlations、title citation、
inbox splice と未 admission claim、first-level fork の両方の未完了 tool outcome、assistant-less provider failure / cancellation、
interrupted tail、restore source/creation tampering、malformed archive rejection を確認します。CLI は大容量 file と FIFO の拒否も確認します。
MoonBit white-box test は importer の不変条件と内部所有権を JS / native / Wasm / Wasm GC の全 target で実行します。
もう 1 本の integration test は app の `stop` / `start` をまたぐ古い effect が新しい session を更新できないことを検証します。

## 実 Chromium 検証

`web/browser-smoke.mjs` **PASS / exit 0 (2026-10-07)**。実際の browser、HTTP server、MoonBit engine / API / gpui scene、Canvas を使用しました。
provider response は固定 fixture です。file write は test 用の一時ディレクトリで本当に実行します。

確認範囲:

- create / select / send / complete と入力中 draft の保持。
- upstream Session v4 import 後の read-only status / composer、transcript、provider を呼ばない continuation refusal。
- New session の処理中に active session を明示的に選び直した場合の selection-intent race。
- 承認前にはファイルが存在しないこと、Allow 後に作成されること、Deny では作成されないこと。
- provider 処理の cancel、HTTP 503 の表示。
- gated provider response の EOF 前に provisional text / reasoning と accessible writing label が見え、EOF 後に同じ turn の final row だけが残ること。
- `<script>` の文字列が実行されずに表示されること。
- Canvas scroll と Text view の読書位置、create と select の応答順の競合。
- 390px viewport で横 overflow がないこと。
- 接続失敗からの Reconnect と選択中 session の保持。

再実行には任意の development dependency として Playwright と Chromium を用意します。
通常の build / test にこの依存は不要です。

```sh
npm install --no-save --package-lock=false playwright
npx playwright install chromium
npm run build
node web/browser-smoke.mjs
```

既存の Chromium を使う場合は `PLAYWRIGHT_CHROMIUM_EXECUTABLE` に executable を指定します。
この実行環境では browser CDN の応答が HTML だったため、既に入手済みの Playwright Chromium executable を指定して検証しました。
browser / host / HTTP server / test workspace は終了時に後片付けします。
画像は `_build/browser-smoke/` に生成し、desktop approval と mobile transcript を目視確認しています。

## Bounded parallel read-tool increment

2026-10-07、pinned upstream の parallel dispatch を bounded Read pool として実装した差分で `npm test` **PASS / exit 0**。
すべて keyless fixture で実行し、外部 provider API は呼び出していません。

| gate | 結果 |
| --- | --- |
| `npm run check` | PASS。all-target MoonBit check、own warnings 0、JavaScript syntax 28 files。固定 hotpath diagnostics のみ。 |
| `npm run test:moon` | Wasm、Wasm GC、JS、native それぞれ 84 / 84 PASS。 |
| `npm run build` | PASS。compiled MoonBit ESM を生成。 |
| `npm run test:host` | 40 / 40 PASS。4-effect read pool の共有 checkpoint、cancel、shutdown と no-replay を確認。 |
| `npm run test:web` | 9 / 9 PASS。 |
| `npm run test:integration` | 44 / 44 PASS。pinned upstream parallel-tool-calls fixture の runtime/read/result/context/reopen 経路を含む。 |

MoonBit tests は rolling 4-effect cap、pool refill、out-of-order completion 後の call-order projection、write approval barrier、unknown / schema-invalid barrier、
cancel/restore/double-reopen、容量終了時に保存済み成功を保つこと、異なる tool safety policy と unresolved Write / Shell barrier を越える forged Read dispatch を拒否することを確認します。
Host tests は一括 checkpoint 失敗時に 4 個の tool effect を起動しないこと、実行中 pool の cancel / shutdown と queued sibling の no-replay を確認します。
この差分は `plugins/` を変更していないため、`npm run mutation` は再実行していません。同コマンドは production plugin package のみが対象で、engine mutation coverage は含みません。

## Manual tool-result pruning increment

2026-10-07、pinned upstream tool-result pruner の explicit v1 subset を追加した状態で `npm test` **PASS / exit 0**。
すべて keyless fixture で実行し、外部 provider API は呼び出していません。

| gate | 結果 |
| --- | --- |
| `npm run check` | PASS。all-target MoonBit check、own warnings 0、JavaScript syntax 28 files。固定 hotpath diagnostics のみ。 |
| `npm run test:moon` | Wasm、Wasm GC、JS、native 各 target で 89 / 89 PASS。app JS に test entry はありません。 |
| `npm run build` | PASS。 |
| `npm run test:host` | 40 / 40 PASS。 |
| `npm run test:web` | 10 / 10 PASS。 |
| `npm run test:integration` | 44 / 44 PASS。 |
| `web/browser-smoke.mjs` | PASS。実 Chromium、local host、fixture provider response を使用。 |

`tests/integration/upstream-parallel-tools.test.mjs` は実際の local HTTP provider body を capture し、2 件の 10,000-character Read result が
call order を維持したまま bounded request context になることを確認します。full original は `Session.messages()` と persisted snapshot に残り、
prune operation は host の serialized checkpoint path を通ってから返ります。completed session を reopen した後の provider context も同じで、
read tool が再実行されないことを確認します。Session v4 importer に対する mutation は read-only error として拒否します。
MoonBit white-box tests は Unicode code point / marker-only budget、idempotence / tighter chained budget、invalid input、event capacity、
wrong call / forward or unrelated result reference、forged content / count / budget、duplicate pruning event の restore rejection を確認します。
全拒否ケースで live snapshot または restore target は部分更新されません。

Browser smoke は **Trim outputs** の原文表示と context projection を確認し、session 切替時に古い notice を消します。
成功した idempotent prune の遅延応答と、保存容量で失敗する prune の遅延応答の両方を別 session への切替と競合させ、
元 session 向けの success / error notice が選択中の session に表示されないことを確認します。
この機能は manual trigger のみで、token meter、pressure trigger、自動 compaction、summary、spill は実装しません。pruning event が追加保存量を使うため、
262,144 UTF-16 code unit / 32,768 event の上限は維持されます。mutation gate の production scope は `plugins/plugins.mbt` のみで、
今回その plugin source を変更していないため再実行していません。

## turtles.mbt mutation gate

`npm run mutation` **PASS / exit 0**。

| 項目 | 結果 |
| --- | ---: |
| Production scope | `plugins/plugins.mbt` |
| Backend | native |
| Mutants | 35 |
| Killed | 27 |
| Survived | 0 |
| Timeout | 0 |
| Unviable | 8 |
| Viable mutation score | 100%（27 / 27） |

unviable は compile できない mutation であり、テストが検出したものとして数えません。
これは plugin package に限定した gate で、engine / provider / UI / host 全体の mutation coverage を意味しません。

固定 turtles を source から build し、production plugin source と同じ tests を一時 module にコピーして実行します。
workspace 内の OS 専用 vendor backend を baseline に混ぜないための分離です。
source の簡略版、未接続の sample、列挙だけの dry-run は使いません。

最終入力の SHA-256:

| ファイル | SHA-256 |
| --- | --- |
| `plugins/plugins.mbt` | `fd8851982927d6f1ff09bb6ff123a7cd6b2f2a9fddb3ae098391db94e705ea34` |
| `plugins/plugins_test.mbt` | `cb1351c4cfac22ea73ab035a62cf8469f8fec53ba7037145a05f2d4982a8bc52` |
| `plugins/moon.pkg` | `eb7eac625d27fc2f0ba4dee491d4c727d8891042a7adb5909165207dd0088562` |
| `turtles.toml` | `06a3a9f8ea987a008a95fe8bce69e52c05d83765fdef76d892533de2ad6127c4` |

再実行の report、input hash、mutant diff は `_build/mutation/plugins/`。
`.github/workflows/mutation.yml` は手動起動用で、同じ gate の結果を artifact として保存します。

## 独立レビューで修正した不具合

- app 再起動で effect ID が再利用され、古い completion が新しい turn に届く問題。
- 大きな履歴で engine 更新後に gpui output 上限に達し、I/O が開始されない問題。
- 大きな tool output に truncation marker を加えると上限を超える問題。
- checkpoint 待機中に shutdown し、その後に新しい I/O が始まる問題。
- 同一 facade の同時 startup で ownership check をすり抜ける問題。
- 過去の不正 tool arguments が、対応する tool error の後の provider 再送を妨げる問題。
- browser の ResizeObserver、draft、scroll、select と応答順に関する競合。
- plugin ID 境界、重複、unknown effect、additionalProperties の test 不足。

容量対策は、各 session に 65,000 文字の日本語応答を 2 回含む 32 sessions でも独立に再確認しました。
snapshot は 8,373,042 UTF-16 code units / 25,013,554 UTF-8 bytes、一覧応答は 2,700 文字。
restore は成功し、effect の再発行は 0 でした。

## 未実行・未実装との区別

- **未実行:** 実 API key による有料 provider 接続。
- **未実装:** native window、自動 Session v4 migration / writer と importer が拒否する event semantics、v0–v3 migration、動的 Cordis / npm plugin、subagent、live context compaction、spill、attachment など。
- **対象外:** gpui の全 OS backend / example の検証。portable package の native PASS を native UI の実機 PASS として扱いません。

全機能の対応表は [移植状況](port-status.md)、後続の受入条件は [残りの移植作業](../issues/open/0001-upstream-parity.md) にあります。

## 2026-10-07 Native v1 settled session fork increment

The session_fork command forks a settled, non-imported native v1 session into an independent idle session. This is a scoped runtime feature, not full Session v4 writer or upstream runtime parity. All checks use local or synthetic fixtures; no live provider account, API key, Tailnet, or external tool was used.

| Gate | Result |
| --- | --- |
| npm test | PASS / exit 0. MoonBit tests: 140 / 140 on Wasm, Wasm GC, JS, and native; additional native runtime suite: 48 / 48; host: 42 / 42; web: 33 / 33; integration: 44 / 44. |
| npm run check | PASS. Formatting, all-target MoonBit checks, and JavaScript syntax checks passed; project-owned warnings: 0. The pinned vendor/hotpath dependency emits its existing deprecation warnings. |
| npm run build | PASS. App and shared client JavaScript release bundles built. |
| moon info engine api --frozen | PASS. Updated engine/pkg.generated.mbti exposes EngineCommand::ForkSession and EngineEventKind::SessionForked. |
| node --test web/remote-app-auth.test.mjs | PASS, 15 / 15. Includes explicit A→B→A selection intent winning over a delayed remote fork response. |
| web/browser-smoke.mjs | PASS with real cached Chromium and Playwright; fixture provider only. Covers forked transcript, immutable parent, remapped effect identity, delayed response/session-switch fencing, and the existing browser acceptance flow. |

The browser smoke command on this macOS arm64 workstation was:

```sh
env NODE_PATH='/Users/fu2hito/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules' PLAYWRIGHT_CHROMIUM_EXECUTABLE='/Users/fu2hito/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' node web/browser-smoke.mjs
```

The two executable paths identify this machine's bundled Playwright and cached Chromium; use the equivalent local paths elsewhere. The smoke test serves the local browser app and uses a temporary workspace plus deterministic provider responses. Its file-write fixtures stay inside that temporary workspace, which the test removes on exit. npm test does not require Playwright or a browser and does not include this optional smoke.

Fork creation copies the validated fixed source prefix, transcript, tool correlation, and pruning references. Effect and retry identities are branch-local; approval, active work, retry waits, and imported histories are not inherited. Restore validates marker boundaries, parent settings, the effect map, missing parents, and lineage cycles before adopting a snapshot. The native remote command receipt is replayed after reopen without re-executing effects. The local upstream-parity issue remains open; seeded Session v4 forks, v4 writing, and the other listed runtime features remain separate work.

## 2026-10-07 issue #9 / #11 implementation candidate

Local checks ran on the macOS arm64 development host with MoonBit compiler/core 0.10.14+7d59c7ec9; Ubuntu CI results are listed separately below. Unless stated otherwise, checks use synthetic identities, local servers, and keyless fixtures.

| Check | Result |
| --- | --- |
| Ubuntu 24.04 native-without-node CI | PASS on commit `8dc1ea7744ae7902938afe4b3071fabff0340b51` ([Actions run](https://github.com/f4ah6o/dsh.mbt/actions/runs/37589966829)). The container confirmed Node/npm were absent; native check had zero own warnings, 159 / 159 tests passed, and native/app/client builds, CLI help, and the offline checkpoint/approval/tool/context/reload demo passed. The Linux process fixtures exercised the hard worker resource boundary. |
| Ubuntu 24.04 portable-and-host CI | PASS on the same commit and Actions run: 128 / 128 MoonBit tests on Wasm, Wasm GC, JS, and native; 31 additional native suite cases; host 42 / 42; web 17 / 17; integration 44 / 44; own warnings 0 and JavaScript syntax 34 files. |
| Final `npm test` | PASS / exit 0 at source candidate `10d8a6c94eb2d95f2086166e430e63275d82e0bd`: 128 / 128 MoonBit tests on each of Wasm, Wasm GC, JS, and native; 31 additional native suite cases; host 42 / 42; web 17 / 17; integration 44 / 44; own warnings 0; JavaScript syntax 34 files. Log: `/private/tmp/dsh-final-npm-r5-20261007-01a11483.log`. |
| MoonBit-only native verifier entry point | PASS / exit 0. Format and native package check passed with zero project warnings and three pinned hotpath warnings; native test matrix 159 / 159; native release build and CLI help passed; app and client JS release builds passed; offline native checkpoint/approval/tool/context/reload demo passed. |
| Native verifier with Node/npm removed from PATH | PASS / exit 0. `/bin/sh` asserted that neither Node nor npm was available with PATH limited to Moon and OS tools. The local verifier passed format/check, 159 / 159 native tests, native/app/client builds, CLI help, and checkpoint/approval/tool/context/reload demo using its warm Moon cache. Cold CI runs only the standalone `.mbtx` wrapper non-frozen to resolve its separate imports; internal repository checks/builds remain `--frozen`. Log: `/private/tmp/dsh-final-no-node-r5-20261007-01a11483.log`. |
| Native shutdown and uncertain receipt recovery | PASS. SIGINT/SIGTERM fixture exited 0, terminated its TERM-ignoring child, and reopened an uncertain receipt without replaying effects. Included in the 159 native verifier tests. |
| OAuth/JWKS and credential rotation fixtures | 10 / 10 PASS, including valid and rejected synthetic RS256 claims, callback binding, JWKS rotation, bounded HTTP body/timeouts, and rotated-refresh rollback after sign-in checkpoint failure. Local HTTP fixture execution used elevated loopback access; no OpenAI live credentials were read. |
| PWA service worker and browser view-model tests | 17 / 17 PASS after the bounded whole-asset refresh fix. Tests cover same-URL update, offline generation fallback, partial refresh rollback, in-flight worker install, stalled body, and API/SSE/command/credential cache exclusions. |
| Retry bound proof | PASS, 1 package / 1 goal proved with Z3 4.12.6. This proves only the implementation-connected bounded retry helper and its stated assumptions. |
| Production plugin mutation gate | PASS: 35 mutants, 27 killed, 8 unviable, zero survivors, zero timeouts. Scope is production plugins only, not the typed engine, provider, OAuth, or native runtime. |
| Engine native benchmark | Typed trace 86.06 ± 1.66 µs; compatibility JSON trace 86.41 ± 1.61 µs; ten samples. The intervals overlap; no speedup is claimed. Whole command max RSS was 286,081,024 bytes, including Moon build/tooling; per-operation allocation was not measured. |
| Swift / iOS embedding checks | Parent reported the macOS generated-C harness passed three URLProtocol cases plus UTF-8/NUL and stale-handle ABI checks. Xcode Simulator build/install/launch also passed for the current SwiftUI + MoonC embedding spike. These are not physical-iPhone acceptance; the formal gpui iOS host, IME, accessibility, device memory, and lifecycle gates remain unimplemented or unrun. |

The local regression runs and both Ubuntu Actions jobs pass; the Ubuntu results tested commit `8dc1ea7744ae7902938afe4b3071fabff0340b51` ([run](https://github.com/f4ah6o/dsh.mbt/actions/runs/37589966829)). Live SIWC, actual Tailscale Serve, formal gpui iOS host, and physical iPhone gates remain unrun or unimplemented.
