# 検証記録

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

`web/browser-smoke.mjs` **PASS / exit 0 (2026-10-06)**。実際の browser、HTTP server、MoonBit engine / API / gpui scene、Canvas を使用しました。
provider response は固定 fixture です。file write は test 用の一時ディレクトリで本当に実行します。

確認範囲:

- create / select / send / complete と入力中 draft の保持。
- upstream Session v4 import 後の read-only status / composer、transcript、provider を呼ばない continuation refusal。
- New session の処理中に active session を明示的に選び直した場合の selection-intent race。
- 承認前にはファイルが存在しないこと、Allow 後に作成されること、Deny では作成されないこと。
- provider 処理の cancel、HTTP 503 の表示。
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
この実行環境では browser CDN の応答が HTML だったため、既に入手済みの完全な Chrome Headless 153 archive を展開して検証しました。
browser / host / HTTP server / test workspace は終了時に後片付けします。
画像は `_build/browser-smoke/` に生成し、desktop approval と mobile transcript を目視確認しています。

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
