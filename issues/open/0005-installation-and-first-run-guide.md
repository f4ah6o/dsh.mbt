# 0005: CLI と macOS アプリの配布を区別し、初回起動まで案内する

状態: proposal / open。実装・実行テストは未実行。
Updated: 2026-10-11
Baseline: `003e25b1113f0a252b6889f4e13f76f135d6a795` (`main`)
観測対象: macOS Apple Silicon / moon-binstall v0.1.6 / dsh v0.1.16

## 目的

インストール後に利用者が Web / CLI / desktop のどれを使えるか判断し、追加導入が必要ならその手順へ進めるようにする。リポジトリ名・registry 名・実行名の違いを覚えないと起動できない状態を解消する。

## 観測事実

1. ログでは `moon binstall f4ah6o/dsh.mbt` が `dsh-darwin-aarch64` を導入し、`Installed .../dsh` を表示した。
2. 続けて `dsh desktop` を実行すると Dsh.app 未導入で終了した。利用者が別配布を認識できる案内は、提示されたインストール完了表示にはない。
3. [README](../../README.md) は `moon binstall dsh` を案内する一方、moon-binstall v0.1.6 は GitHub 用に明示的な owner/repo を要求する。
4. [desktop guide](../../docs/desktop.md) には、別配布の `Dsh-macos-arm64.zip` を取得し `/Applications` または `~/Applications` に配置する説明がある。説明は存在するが、初回起動の入口から見つけにくい。

`f4ah6o/dsh` への curl exit 56 は通信エラーとして観測されており、repository 404 だったとは断定しない。

## 実装範囲

1. README の導入節を source build より前で見つけられる位置に置き、実際に対応する `moon binstall f4ah6o/dsh.mbt` と source install の違いを明示する。
2. 次の名称対応表を README と配布案内で一致させる。

| 用途 | 名称 / 成果物 |
| --- | --- |
| GitHub repository / binary install coordinate | `f4ah6o/dsh.mbt` |
| Mooncakes module | `f4ah6o/dsh` |
| Mooncakes command package | `f4ah6o/dsh/cmd/dsh@VERSION` |
| CLI executable | `dsh` |
| macOS desktop release archive | `Dsh-macos-arm64.zip` |
| installed app bundle | `Dsh.app` |

3. CLI binary に Web assets が含まれ、Dsh.app は含まれないことを導入時に説明する。Web は checkout 不要で起動できることを記載する。
4. README・GitHub Release の説明から、Web の最小起動例と macOS archive の取得・展開・配置・起動へ直接進めるようにする。固定の古いバージョンと最新例を混在させず、release workflow の生成内容も確認する。
5. 実行中に参照されるヘルプ / desktop 未導入メッセージには、配布 guide と正確な archive 名への導線を置く。メッセージの終了処理は 0006、用途別ヘルプは 0004 と連携する。
6. Apple Silicon / macOS の対応条件と既存の署名・初回起動手順を簡潔に維持する。実装予定の installer 機能を、現在使えるコマンドとして掲載しない。

汎用 moon-binstall の成功表示を dsh 固有文言で変更することは、このリポジトリの実装範囲ではない。まず dsh が所有する README / release notes / CLI guide を揃える。

## 受入条件

- [ ] README の binary install 例と release asset contract が一致し、非対応の `moon binstall dsh` を動作例として残さない。
- [ ] install の説明だけで CLI / embedded Web / 別配布 Dsh.app の対応を判別できる。
- [ ] README と release notes にコピー可能な Web 起動例、desktop archive 名、配置先、起動例がある。
- [ ] インストール済み CLI と Dsh.app 未導入の状態から、正しい追加導入手順に到達できる。
- [ ] release binary を checkout 外の一時 workspace から起動して Web assets が配信される。
- [ ] desktop 手順で対応版アプリが見つかり、明示 workspace を渡して起動できる。
- [ ] source install を事前に行わなくても、記載された binary install 手順が成立する。

## 検証計画

未実行。実装 PR で README のコマンド /リンク、[publish-native workflow](../../.github/workflows/publish-native.yml) の release 説明、[release CLI smoke](../../scripts/smoke-release-cli.sh)、[macOS smoke](../../scripts/smoke-release-macos.sh) を確認する。ネットワークを使う実 release 導入と macOS 実機起動の結果は、fixture テストと区別して記録する。

## 関連と境界

- [0004: 用途別ヘルプ](0004-task-oriented-cli-help.md)
- [0006: desktop エラー終了](0006-desktop-launch-recovery.md)
- moon-binstall の `issues/open/0002-coordinate-discovery-and-guidance.md` は installer 側の座標説明を担当する。名称表を共有するが、両 PR の merge を待たずに正しい現行コマンドを案内できる。
- Dsh.app の自動ダウンロード / 自動インストール、新しい認証方式、UI 機能の追加は対象外。
