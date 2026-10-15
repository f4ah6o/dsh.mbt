# dsh.mbt：hobby appとして使い、開発toolを製品依存へ戻さない

Status: open — 設計課題。hotpath分離済みの現状を前提に、継続する境界と回帰検証を定義する。
Priority: P1
Decision date: 2026-10-15
Parent: [ecosystem方針・共通マージ基準](https://github.com/gpui-mbt/gpui.mbt/pull/82)

## 1. 役割

dshはDeepSeek HarnessのMoonBit移植を趣味の実アプリとして育てる場所。gpui.mbtとYami-kumoを実際に使って不足を見つけるが、ecosystemの全機能を試すためにアプリを複雑化しない。MZedが部分置換の技術PoC、dshが日常的なhobby consumerという役割分担にする。

hobbyであることは、認証・データ保護・tool approval・テスト基準を緩める理由ではない。dsh固有機能の完成を他repoの無関係な改善の必須gateにもせず、対応consumerとして必要な互換性検証は維持する。

## 2. 現状確認（2026-10-15）

1. [moon.mod](../../moon.mod)の通常importはgpui、async、Yami-kumoであり、hotpathとturtlesを直接含まない。
2. [README](../../README.md)はhotpathが通常アプリ依存ではなく、`profile_stats`を削除済みと説明している。
3. [tools/perf](../../tools/perf/README.md)は独立した任意module/workspace。明示して初期化する`vendor/hotpath`を使い、通常module/workspaceはhotpathを解決しない。製品archiveからの除外も記載されている。
4. [補足コメント](https://github.com/f4ah6o/dsh.mbt/pull/65#issuecomment-6189669670)が参照する[PR #64](https://github.com/f4ah6o/dsh.mbt/pull/64)は[merge commit `e8c5bd0e5959b0525df3b2e0dd9908f9a6aa149b`](https://github.com/f4ah6o/dsh.mbt/commit/e8c5bd0e5959b0525df3b2e0dd9908f9a6aa149b)で取り込まれている。分離だけでなく、[既存の境界検査](../../scripts/check-performance-boundary.py)と[CIへの組込み](../../.github/workflows/ci.yml)も再利用対象である。
5. 既存検査は`moon tree --json`による解決graph、`moon package --frozen`のsource archive、`tools/perf`と`vendor/hotpath`の除外、fresh archive consumerのgraph一致と`moon check api --target all --frozen --deny-warn`を確認する。禁止moduleは現在hotpathとdsh_perfであり、全開発toolへの検査拡張を完了したとはしない。
6. fresh archiveのAPI typecheckは、そのarchiveからの製品全体のbuild・help・keyless demoの実行証拠とは別である。既存CIは通常build/testとoptional perf fixtureも実行するが、recursive submoduleを取得したcheckoutでの成功だけでは開発toolが存在しないconsumer環境の動作を証明しない。
7. したがってhotpath削除や境界検査の再実装はしない。残る作業は既存検査の拡張、開発toolなしのconsumer/package runtime smoke、依存の再混入を検出する反例である。`profile_stats`を戻さず、独立perf fixtureをproduction telemetry endpointの代替にしない。

## 3. 境界

1. 製品の会話・session・provider・approval・persistenceはdshが所有する。汎用UIのengine問題はgpui.mbt、共通UXはYami-kumoへ最小fixtureで返す。
2. **turtlesはmutation testing、hotpathは性能計測の開発tool**。vlmkitとgpui-conformanceも開発／検証側。通常アプリのinstall・build・launch・配布物に必須化しない。
3. 製品に必要なgpui／Yami-kumo／OSライブラリは残す。「開発toolを外す」を全依存削除や既存public APIの無関係な変更に拡大しない。
4. `tools/perf`はopt-inを維持する。テスト専用importやruntimeでの無効化だけを依存除去と呼ばない。未文書の`devDependencies`設定を仮定せず、独立module/workspaceで分離する。
5. 計測のために削除済み`profile_stats`や常時計測を復活させない。通常のengine APIを外側から計測する。

## 4. 実装単位

1. **既存境界検査の拡張**：`scripts/check-performance-boundary.py`を再利用し、product module、workspace、解決した推移的依存、package import、配布archiveの不足する検査だけを追加する。既存hotpath/dsh_perf検査と別の重複validatorを作らない。必要に応じて他の開発toolの禁止moduleを追加し、通常importやworkspace memberへの再混入を専用一時fixtureで検出する。文書中の名前への単純grepだけで依存を判断しない。
2. **開発toolなしのconsumer/package smoke**：既存のfresh archive API typecheckを土台に、optionalな`tools/perf`と`vendor/hotpath`が存在しない環境で製品全体のbuild・help・keyless demoを確認する。source archiveと配布binaryの検証を分ける。必要なgpui等は用意し、開発toolと製品依存を区別する。ユーザーの作業treeから削除して試さない。
3. **独立した開発経路**：READMEの通常手順がoptional hotpath初期化やturtles導入を必須化しないよう整理する。性能計測はtools/perf、mutationは外部CLI、GUI検証は別profileで明示実行する。既存CIのoptional perf検証は維持し、製品利用に必要な手順と混同しない。
4. **実利用からの還元**：小さなkeyless conversation／session表示等のfixtureから、UI不具合とアプリ固有不具合を切り分ける。最小再現と候補SHAを担当repoへ渡し、MZedや外部providerの実アカウントを必須にしない。

## 5. 受入条件

| 対象 | 合格条件 |
| --- | --- |
| 通常module/workspace | hotpath/turtles/vlmkit/conformanceを通常依存として解決しない。既存hotpath/dsh_perf検査を維持する |
| 製品build/run | optional開発toolが存在しないfresh consumerで、必要な製品依存だけを解決してbuild・help・keyless demoが動く |
| 配布物 | 開発用module・optional vendor・開発tool実行ファイルを含めず、配布後に開発tool導入を要求しない |
| perf経路 | 明示したtoolだけを導入し、独立moduleから既存HarnessApiを計測できる |
| regression | hotpath等の通常import／workspace member再追加を隔離fixtureで検査が検出し、元の作業treeを変更しない |
| product API | 削除済みprofile_statsを復活させず、既存会話・承認・保存動作を維持する |
| 速度の報告 | 計測条件・生sample・不確実性を示し、依存削除や既存perf fixture成功だけで高速化と主張しない |

配布archiveについてはsource packageとbinary assetを区別して検査し、source buildに必要な正当な製品依存まで除外しない。既存graph/archive/API検査、fresh consumer runtime smoke、binary smoke、perf比較を別の結果として残し、一つの合格を他の合格へ読み替えない。

## 6. 検証方法

既存の境界検査は`python3 scripts/check-performance-boundary.py`。通常経路はREADMEの`moon update`、`moon install`、`sh scripts/build.sh`とkeyless demo手順を、必要な製品依存だけがあるfixture環境で実行する。独立perf経路は既存手順を維持する。

```sh
git submodule update --init --recursive -- vendor/hotpath
moon -C tools/perf install
moon -C tools/perf test trace --target native
moon -C tools/perf run cmd/profile --target native --release
moon bench benchmarks/engine_core --target native --release
```

上記optional経路の成功は製品利用時の通常buildの必須条件ではない。開発CIでの実行とは分けて扱う。ローカル実行とCI内の実行を区別し、実際のjob/step・対象・コマンド・候補SHA・PASS/FAIL/未実行と理由を記録する。文書PRのCI成功を新しいconsumer受入や性能回帰検証の完了とはしないが、CIで実行済みのbuild/test/perfまで未実行に読み替えない。

## 7. マージ基準・完了条件

共通`ecosystem-merge-v1`に従い、**最新HEADの必要CIがすべてcompleted/success AND 同じHEADに対する実際の`gpt-6.1-sol/xhigh`レビューのApprove相当**を必要とする。モデル・effort・SHA・判定・指摘処置・証拠URLをGitHubへ記録する。P0/P1、必要checkのskip、未実行、古い承認を合格にせず、HEAD更新後は再検証・再レビューする。hobbyでも既存の保護を維持する。

1. [ ] 既存graph/archive/API検査を維持し、開発toolなしのfresh consumer build・runと配布物smokeを追加検証する。
2. [ ] optional perf／mutation／GUI検証の導線を通常利用と分ける。
3. [ ] 通常依存の再混入をnegative testで検出する。
4. [ ] アプリで見つけた汎用UI不具合を担当repoへ還元する導線がある。
