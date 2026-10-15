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
4. したがって「hotpathをこれから全面削除する」課題にはしない。通常build/run／配布物からの分離を壊さない検査と、開発経路の案内を扱う。依存graph全体・実配布物の動作はこの文書追加では再実行していない。

## 3. 境界

1. 製品の会話・session・provider・approval・persistenceはdshが所有する。汎用UIのengine問題はgpui.mbt、共通UXはYami-kumoへ最小fixtureで返す。
2. **turtlesはmutation testing、hotpathは性能計測の開発tool**。vlmkitとgpui-conformanceも開発／検証側。通常アプリのinstall・build・launch・配布物に必須化しない。
3. 製品に必要なgpui／Yami-kumo／OSライブラリは残す。「開発toolを外す」を全依存削除や既存public APIの無関係な変更に拡大しない。
4. `tools/perf`はopt-inを維持する。テスト専用importやruntimeでの無効化だけを依存除去と呼ばない。未文書の`devDependencies`設定を仮定せず、独立module/workspaceで分離する。
5. 計測のために削除済み`profile_stats`や常時計測を復活させない。通常のengine APIを外側から計測する。

## 4. 実装単位

1. **通常consumerの境界検査**：product module、workspace、解決した推移的依存、package import、配布archiveを検査する。開発toolが通常graphへ入ったらfailする。文書中の名前への単純grepだけで依存を判断しない。
2. **開発toolなしのsmoke**：専用fresh checkout／展開した製品packageで、optionalな`tools/perf`と`vendor/hotpath`を用意せず通常build・help・keyless demoを確認する。既存の必要なgpui等は用意し、開発toolと製品依存を区別する。ユーザーの作業treeから削除して試さない。
3. **独立した開発経路**：READMEの通常手順がoptional hotpath初期化やturtles導入を必須化しないよう整理する。性能計測はtools/perf、mutationは外部CLI、GUI検証は別profileで明示実行する。
4. **実利用からの還元**：小さなkeyless conversation／session表示等のfixtureから、UI不具合とアプリ固有不具合を切り分ける。最小再現と候補SHAを担当repoへ渡し、MZedや外部providerの実アカウントを必須にしない。

## 5. 受入条件

| 対象 | 合格条件 |
| --- | --- |
| 通常module/workspace | hotpath/turtles/vlmkit/conformanceを通常依存として解決しない |
| 製品build/run | optional開発toolなしで必要な製品依存を解決し、build・help・keyless demoが動く |
| 配布物 | 開発用module・optional vendor・実行ファイルを含めず、配布後にcloneや開発tool導入を要求しない |
| perf経路 | 明示したtoolだけを導入し、独立moduleから既存HarnessApiを計測できる |
| regression | hotpath等の通常import／workspace member再追加を検査が検出する |
| product API | 削除済みprofile_statsを復活させず、既存会話・承認・保存動作を維持する |
| 速度の報告 | 計測条件・生sample・不確実性を示し、依存削除だけで高速化と主張しない |

配布archiveについてはsource packageとbinary assetを区別して検査し、source buildに必要な正当な製品依存まで除外しない。

## 6. 検証方法

通常経路はREADMEの`moon update`、`moon install`、`sh scripts/build.sh`とkeyless demo手順を、必要な製品依存だけがあるfixture環境で実行する。独立perf経路は既存手順を維持する。

```sh
git submodule update --init --recursive -- vendor/hotpath
moon -C tools/perf install
moon -C tools/perf test trace --target native
moon -C tools/perf run cmd/profile --target native --release
moon bench benchmarks/engine_core --target native --release
```

上記optional経路の成功は通常buildの必須条件ではない。通常経路が通ることと性能計測が通ることを別結果にする。この文書追加では上記コマンドは未実行。実装時は対象・コマンド・候補SHA・PASS/FAIL/未実行と理由を残す。

## 7. マージ基準・完了条件

共通`ecosystem-merge-v1`に従い、**最新HEADの必要CIがすべてcompleted/success AND 同じHEADに対する実際の`gpt-6.1-sol/xhigh`レビューのApprove相当**を必要とする。モデル・effort・SHA・判定・指摘処置・証拠URLをGitHubへ記録する。P0/P1、必要checkのskip、未実行、古い承認を合格にせず、HEAD更新後は再検証・再レビューする。hobbyでも既存の保護を維持する。

1. [ ] 通常build・run・配布物の開発tool非依存を回帰検証する。
2. [ ] optional perf／mutation／GUI検証の導線を通常利用と分ける。
3. [ ] 通常依存の再混入をnegative testで検出する。
4. [ ] アプリで見つけた汎用UI不具合を担当repoへ還元する導線がある。
