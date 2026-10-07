# 0003: MoonBit native kernel と iOS / Tailscale クライアントへのロードマップ

状態: open（proposal。設計レビュー用であり、実装・対応済みの宣言ではない）
Updated: 2026-10-07
Baseline: `71a33a565455e167fa9dd687155fa794b6cc2414` (`main`)
Guide baseline: `moonbitlang/moonbit-agent-guide@7262fb823452c20ffb6a01d4b06f9de639e7c774`
関連: [0001 upstream parity](0001-upstream-parity.md)、[認証提案 PR #9](https://github.com/f4ah6o/dsh.mbt/pull/9)、[gpui.mbt モバイル設計 PR #43](https://github.com/gpui-mbt/gpui.mbt/pull/43)

## 1. 目的と設計方針

Node.js I/O host を MoonBit native runtime に置き換え、iPhone / iPad を正式な操作環境にする。実行ホストは Mac / Linux を先行し、端末間は Tailscale の tailnet 内で接続する。

単に `.mjs` を `.mbt` に翻訳するのではなく、型付きの操作・状態・外部作用、構造化された非同期処理、決定的な再現、複数 backend で共有する client を設計の中心に置く。

1. **実行はホスト、操作は端末。** iPhone のロック、アプリ終了、通信切断では agent を停止しない。明示的な停止要求とホスト shutdown は別の操作にする。
2. **互換性は外部契約に対して守る。** provider wire、承認、安全性、履歴の意味を維持する一方、JS FFI のためだけの内部 String / Json 往復や状態表現は作り直す。
3. **MoonBit の共通コードを両側で使う。** protocol だけでなく、表示用 projection、接続・再同期・送信状態、下書きと選択状態も共有する。権限・秘密情報・実 I/O はサーバー側に置く。
4. **PWA を第一到達点、iOS native を後続の正式目標とする。** native 組込みの小さな検証は最初から並行し、PWA 完成後まで技術的な不確実性を放置しない。
5. **追加する外部 MoonBit ライブラリは公式のみ。** 不足は公式への小さな拡張、または dsh 内部の実装で補う。特定の第三者作者を例外扱いしない。

この文書の package / type / command 名は設計候補であり、新しい公開 API や動作するコマンドを示すものではない。

## 2. 現在地と移行対象

上記 baseline のソースを根拠とする。実行による再検証結果ではない。

| 現在の場所 | 確認した構造 | 方針 |
| --- | --- | --- |
| [engine/types.mbt](../../engine/types.mbt)、[engine/engine.mbt](../../engine/engine.mbt) | 状態などに enum がある一方、操作は String / Json、Event は kind と Json payload、Effect は Json request | 既存の意味を保持し、内部操作・ID・イベント・effect・待機状態を型付きにする |
| [provider/README.md](../../provider/README.md) | MoonBit が request / response と incremental SSE decoder を所有 | codec は再利用し、native HTTP stream から直接接続する |
| [app/app.mbt](../../app/app.mbt) | JS 用の文字列 FFI、app incarnation、stream handle と生存期間管理 | application の所有権管理を切り出し、JS は一時的な薄い adapter にする |
| [host/runtime.mjs](../../host/runtime.mjs) | checkpoint、effect 実行、stream queue、retry の実行、shutdown | 公式 async と単一の状態所有者を使う runtime に再設計する |
| [host/tools.mjs](../../host/tools.mjs)、[host/persistence.mjs](../../host/persistence.mjs) | 安全な workspace 操作、子プロセス監督、atomic snapshot と単一 writer | 実 I/O と OS 境界を native 化し、保証を後退させない |
| [host/server.mjs](../../host/server.mjs) | loopback bind、localhost の Host と HTTP Origin の限定、HTTP / MCP carrier | loopback は維持し、設定済みの外部 HTTPS origin と信頼する proxy を扱う |
| [web/app.js](../../web/app.js) | client 状態・polling・選択・表示更新が JS | client の振る舞いを MoonBit に移し、DOM / browser 接続だけを adapter に残す |
| [README.md](../../README.md)、[package.json](../../package.json) | native window は未実装。起動・検証・mutation 起動も Node / npm に依存 | native / PWA の実経路と、Node 不要の開発・配布経路を別々に完了判定する |

[0001](0001-upstream-parity.md) に記載された read-only tool の最大 4 件 rolling pool と call-order の結果確定は既存機能である。並列化自体を新機能として数えず、native 化後も barrier、承認、完了順序の保証を維持する。

## 3. スコープと依存方針

「pure MoonBit」の第一到達点は、アプリケーションの意味・I/O 制御・開発自動化を MoonBit で所有し、Node.js I/O host を必須にしないこと。

公式ライブラリの C / OS / TLS 境界、必要最小限の OS FFI、iOS の platform glue は許容する。公式 async の TLS が用いる OpenSSL まで排除することや、OS・TLS・VPN を MoonBit で再実装することは、この提案の完了条件ではない。C / OpenSSL 依存ゼロとは表記しない。

Web 用に MoonBit から生成する JavaScript は許容する。それは Node.js host の復活ではない。browser glue へ agent loop、同期状態、権限判定を戻さない。

既存の gpui.mbt / hotpath.mbt / turtles.mbt はこのプロジェクトで育てる固定 revision のコードとして維持する。公式外ライブラリを無条件に信頼する例外ではなく、推移的依存・license・native 境界を引き続き検査する。追加外部依存の制約は test / automation 用にも適用する。OS SDK、Tailscale、compiler、既存の検証用実行ファイルは MoonBit ライブラリとは区別して記録する。

初期スコープ外: 公開 SaaS、Funnel、任意ユーザーの multi-tenant hosting、iPhone 内での workspace / shell 実行、常時 background socket の保証、オフラインでの agent 実行、CRDT による全状態の双方向同期、Cordis / npm runtime の再導入、TLS 自作、push 通知の必須化。

[0001](0001-upstream-parity.md) の未実装機能や [PR #9](https://github.com/f4ah6o/dsh.mbt/pull/9) の認証提案を完了扱いにしない。本提案は実行基盤と client の基盤を提供し、それらの機能実装を別に進められるようにする。

## 4. 共通コードと実行境界

```text
iPhone / iPad                       Desktop
MoonBit client + presentation      同じ client / presentation
PWA adapter -> iOS native adapter  local または remote adapter
              |                         |
              +------ HTTPS / tailnet --+
                              |
                       Tailscale Serve
                              | loopback
                     dsh native service
                              |
                  application / capability API
                              |
                  runtime: 状態更新・保存の所有者
                     |                 |
              typed kernel       実 effect の実行
                                       |
                         provider / tools / storage
                                       |
                       公式 async + 最小 OS 境界
```

| 境界候補 | 内容 | 配置・制約 |
| --- | --- | --- |
| `protocol/` | command、receipt、表示イベント、ID、version 付き codec | portable。OS handle / credential を含めない |
| `presentation/` | 許可された状態から会話・進捗・承認表示を構築 | portable。raw snapshot の全面公開を避ける |
| `client/` | 接続・再同期・送信状態、下書き、選択、復元 | portable。I/O は注入し、server の権限判定を代行しない |
| `application/` | typed API、app incarnation、公開入口と所有権 | local / remote adapter の共通入口 |
| `engine/` | 状態遷移、承認、retry 判断、effect 計画 | 純粋な判断部分を分離し、唯一の実装として使う |
| `runtime/` | task lifetime、checkpoint、effect dispatch、終了処理 | native server |
| `tools/`・`storage/`・platform 境界 | workspace、process、snapshot、資格情報 | native server。client から任意パスを指定して拡張しない |
| `ui/` と gpui host adapter | 共通画面構成と OS / DOM の表示・入力接続 | 対応環境を実機で別途認定する |

最初から全 package を新設しない。実際の責務・呼出し元を確認し、凝集した小さな単位にする。循環依存や、runtime から UI への逆依存を作らない。

ローカル UI も同じ操作契約を使い、同一プロセス呼出しと remote transport を切り替えられる形にする。初期版は単一ホスト・単一の登録済み workspace・複数 client を基本とする。複数 workspace を追加する場合も server が登録した ID で指定し、remote 入力から任意の filesystem root を開かない。

## 5. MoonBit らしい再設計

### 5.1. 型で意味を分ける

SessionId、TurnId、EffectId、CommandId、Revision を区別する。内部操作は String dispatch ではなく、所有する型のメソッドや型付き command として表現する。

Event / Effect は必要な payload を持つ enum にし、網羅的な pattern matching で分岐を管理する。read-only imported history と実行可能 session、承認待ちとその承認対象、retry 待ちとその retry identity を対応する状態へまとめ、不正な組合せを減らす。

外部 JSON は境界で一度検証する。provider wire、HTTP / MCP、snapshot には version 付きの明示 codec を残す。enum の自動シリアライズ結果を永続仕様にしない。String / Json の汎用入口が必要な互換 adapter と、typed internal API を区別する。

想定内の拒否・provider failure・tool failure と、storage failure など runtime を止める障害を型で分ける。checked error / Result を用途で使い分け、エラー文言の regex を制御の契約にしない。

実行可能な effect は、承認と必要な durable commit が成功した後にだけ内部で構築する。外部 JSON から生成できる実行許可証にはしない。ただし型を linear type とみなさず、ID 照合、二重完了拒否、世代確認、実行時チェックを残す。型だけで exactly-once を保証したと主張しない。

### 5.2. 決定的な判断とシミュレーション

判断部分を「現在の状態 + 入力 -> 次の状態候補 + 記録イベント + effect 候補」に寄せる。全状態の巨大な deep copy や無制限の immutable 化を必須にせず、更新範囲と atomic な採否を明確にする。

時刻、provider 応答、tool 完了、保存結果を明示入力にする。実行は real adapter、テストは仮想時刻・fake adapter を用い、同じ判断関数を通る。診断 replay は外部作用を実行せず、なぜ retry / dispatch / reject したかを再現できるようにする。

これは Session v4 の read-only import を実行再開へ変更するものではない。診断用 fixture の記録と共有にも redaction・容量制限を適用する。

### 5.3. 構造化された非同期処理

公式 `moonbitlang/async` の task group を利用し、application / turn / effect の生存期間を明示する。状態更新と checkpoint は単一の所有者が順序付け、network / process の callback が直接状態を書き換えない。

provider / tool の想定内エラーは turn の結果へ変換し、無関係な session を巻き込む未処理 task error にしない。storage failure は新規 effect を止める。取得した資源の解放は `defer` などで取得箇所へ対応付けるが、shutdown の順序契約は別に検証する。

durable retry の判断・記録を汎用 retry helper に移さない。kernel が schedule / started を決め、runtime が保存成功後の待機・再接続を行う。

接続 subscriber は run の所有者ではない。subscriber task の終了を turn の cancel と結び付けない。既存の foreground CLI 終了契約と、常駐 service の remote 接続切断を混同しない。

### 5.4. view・pattern matching・計測

SSE / JSONL / bounded output の解析には `BytesView` / `StringView` / `ArrayView` と直接の pattern matching を検討する。状態を持つ走査では functional `for` と明示的な cursor / accumulator を使う。

短命な解析参照は view、長期保持するイベント・メッセージは必要範囲を所有する。小さな view が巨大 buffer を保持し続けることや、buffer 再利用による参照の破壊を避ける。UTF-8 bytes、UTF-16 code units、Unicode scalar 境界は区別する。

hotpath と公式の benchmark / profiling を用い、処理時間、割当量、最大メモリ、表示遅延を同じ fixture・同じ環境で比較する。native 化や view 化だけを根拠に高速化済みとしない。

### 5.5. テスト・仕様・小さな証明

公開契約と black-box test を先に置き、必要な範囲で `spec.mbt` の宣言を使う。`README.mbt.md` / docstring の実行可能な例、`moon info` の `.mbti` 差分をレビュー対象にする。helper は非公開とし、差替えが必要な境界だけを抽象化する。

公式 QuickCheck で操作列・chunk 分割・完了順序を生成し、不変条件を調べる。全 target で対象 package を明示して同じ fixture を検証し、OS adapter は別の integration / 実機試験にする。

`moon prove` の最初の候補は retry 上限、結果確定 cursor、承認・effect 受付の小さな実装関数とする。`.mbtp` のモデルを実際の `.mbt` の契約へ接続し、別の簡略モデルだけを証明して完了としない。対応 toolchain を確認し、証明済み範囲、仮定、未証明範囲を記録する。OS・network・crash の挙動まで証明済みとは扱わない。

### 5.6. 開発自動化も MoonBit

新しく作る automation は `.mbtx` に置き、loops / parsing / process orchestration を shell や JavaScript に再実装しない。公式の shell-free command API で実行ファイルと引数を分離する。これは開発自動化の方針であり、利用者の `bash` tool の意味を変更しない。

候補は `verify.mbtx`、`check-deps.mbtx`、`replay-fixture.mbtx`、`package.mbtx`。存在済みの script ではなく後続実装とする。Wasm host policy を使う場合も、許可された子プロセス自体が sandbox 化されるとは扱わない。

## 6. runtime の保持すべき契約

1. 状態候補を検証し、必要な checkpoint の成功後だけ外部 effect を開始する。保存失敗から新たな provider / tool を開始しない。
2. incarnation、effect、turn、step、call を照合し、古い stream / completion、重複完了を拒否する。
3. stream queue と batch は有限にする。検証済み delta と最終 response を照合し、不完全な tool arguments を実行しない。
4. 現行の read-only rolling pool、write / shell barrier、結果の call-order 確定を維持する。完了順をモデル履歴の順序へそのまま流さない。
5. accepted stream 後の retry 禁止、retry 前の durable 記録、cancel 中の再接続禁止を維持する。
6. cancel / shutdown は受理済み更新、checkpoint、I/O の停止と終了待機を順序付ける。close 後の callback で古い snapshot を上書きしない。
7. ホスト再起動後の未確定 effect は自動再実行しない。client の再接続によってこの方針を変更しない。
8. workspace path、symlink、protected data、ファイル同一性、出力・探索上限を維持する。shell は通常の OS 権限で実行されることを表示し、native 化を sandbox 実装と誤認させない。

## 7. 切断を前提とした remote protocol

### 7.1. 送信・受付・実行完了を分ける

接続状態、command の受付状態、run の状態を別々に持つ。切断時は「最終確認: running / 確認時刻」のように表示し、failed や completed に読み替えない。command の受理応答も tool の完了を意味しない。

command envelope の候補: protocol version、server / workspace / session identity、CommandId、操作 payload、必要な対象 revision。利用者 identity は通信の認証結果から server が確定し、payload の自己申告を使わない。

server は認可後、command receipt と状態遷移を同じ durable transaction へ記録する。同じ利用者・workspace・CommandId と同じ内容なら同じ receipt を返し、同じ ID で内容が変わった場合は拒否する。receipt を先に成功応答し、その後で初めて保存する順序にしない。

重複排除記録には容量・保持期間・失効を設ける。期間を過ぎた不明な ID を新規 command として暗黙に再実行しない。古い ID の判別方法、結果照会、実行結果不明の表示を version 付き契約にする。

切断後は同じ ID の受付結果を照会する。承認は call identity と承認内容の revision に束縛し、別端末で既に解決・変更された要求を拒否する。送信内容・ID は応答未受信時にも照会できる範囲で保持するが、オフライン操作を復帰時に無条件 dispatch しない。特に承認・停止は新しい状態と受付結果を確認して扱う。

command 重複受付の防止は、外部作用の exactly-once 保証ではない。作用後・結果保存前の crash は不確定結果として扱い、人間の確認や明示的な新しい操作を必要とする。

### 7.2. snapshot と連番付き表示イベント

初期 transport は同一 origin の HTTP command / receipt query と SSE の組合せを候補にする。WebSocket や MCP を UI 同期の必須条件にしない。public endpoint 名と wire schema は契約テストとともに確定する。

snapshot には同期 epoch と revision を付け、同じ権限範囲の表示イベントへ cursor を対応させる。snapshot の取得から購読開始までに gap が生じない handoff を server が提供する。重複イベントは無害化し、欠落・逆順・epoch 変更・保持範囲外は再同期へ移る。

cursor は権限範囲に結び付け、filtered event の番号や存在から別の workspace 情報を漏らさない。未対応 protocol version は黙って解釈せず、互換範囲の選択または明示的な更新要求を返す。

server は有限の replay window と subscriber queue を持つ。遅い subscriber のために kernel / checkpoint を停止せず、再同期要求または接続終了で回復させる。SSE の flush、heartbeat、proxy 経由の遅延、再接続中の負荷を検証する。

表示用イベントと raw engine / provider event を区別する。秘密情報・内部診断・別 session の状態を、そのまま全 client に配信しない。認可は初回だけでなく再接続・command・snapshot・イベント購読に適用し、権限失効時に購読を継続させない。

### 7.3. client の最小永続化

下書き、選択中 session、意味上の scroll anchor、最後の cursor、未確認 command ID を server identity / 利用者 / workspace ごとに分離する。provider token や raw engine snapshot を client に保存しない。

履歴のローカル保存は最小化し、保持・削除方針を明示する。PWA の service worker は app shell / versioned asset と認証済み API データを区別し、機密 API 応答を汎用 cache に入れない。browser storage の削除・容量制限を想定し、下書きの永久保持を保証しない。

## 8. iOS の利用体験と gpui.mbt

| 場面 | 受入条件 |
| --- | --- |
| ホーム画面から起動 | 前回の接続先と session を復元し、接続・同期・最新状態を区別して表示する |
| 日本語で依頼 | IME 確定中に誤送信しない。software keyboard / safe area で入力欄・送信操作を隠さない |
| 実行状況を確認 | 現在の tool、retry 待ち、承認待ち、最終更新を表示し、未観測の進捗を推測しない |
| 承認 | 実行ホスト、workspace、ファイルまたは command、承認する引数を確認できる。edit は可能な範囲で変更内容を示す |
| 会話・結果を読む | 選択・コピー・リンク・VoiceOver が通常の操作として使える。stream 更新で読書位置を奪わない |
| 端末をロックして復帰 | run は server 側で継続し、復帰後に再同期する。切断だけで cancel / failed にしない |
| 狭い画面・iPad | 役割付きペインで一覧 / 会話 / 詳細を切替え、余裕のある領域では並べる。機種名の分岐に依存しない |

会話本文・入力を Canvas だけで完結させない。Web は DOM、native は OS のテキスト入力・選択・アクセシビリティとの接続を使い、意味と画面状態は共通 MoonBit 側に置く。native adapter に別の agent / client state machine を実装しない。

[gpui.mbt PR #43](https://github.com/gpui-mbt/gpui.mbt/pull/43) の表示領域・遮蔽・入力 capability・revision・役割付きペイン・surface lifetime の提案と整合させる。dsh を具体的な検証利用先にするが、この PR や MoonBit の backend 数だけを根拠に iOS 対応済みとしない。折りたたみ専用の実装を最初の iPhone 受入の前提にも置かない。

PWA は生成 JS を最初の候補にし、Wasm / Wasm GC の採用は対象 Safari・依存・性能を測って決める。native iOS は C 出力 / ABI / runtime 初期化・破棄 / memory ownership / callback / OS event loop / 通信 adapter を独立検証する。公式 async の desktop 対応を iOS 対応の証拠として使わない。

native の組込み検証では Simulator と実機の両方で、共通 client の最小操作、表示、入力、foreground 復帰を確認する。公式 native library 出力の制約に対しては、検証した C 組込み等の手順を記録し、リンク可能な iOS library が自動生成されるとは仮定しない。共有シート等の OS 連携はその後の追加対象とする。

## 9. Tailscale と認証・認可

基本経路は `iPhone -> tailnet HTTPS -> Tailscale Serve -> loopback dsh service`。Serve と dsh の起動は別に管理する。Tailscale client が両端で接続済みであること、MagicDNS / HTTPS / tailnet の接続許可を運用手順に記録する。設定変更を文書追加だけで実施しない。

1. **Serve のみを前提とし、Funnel を使わない。** `0.0.0.0` への bind や LAN / public port 公開を回避策にしない。
2. **proxy の信頼境界を明示する。** 設定済みの外部 HTTPS origin、信頼する proxy mode、loopback backend を定義する。任意の Host / Origin / Forwarded 値で許可範囲を広げない。現行の localhost 限定チェックを単に削除しない。
3. **identity と権限を分ける。** Serve が与える `Tailscale-User-Login` を、許可した利用者と操作範囲へ server 側で対応付ける。表示名を認証鍵にしない。tailnet に所属するだけで全操作を許可しない。
4. **identity がない場合は拒否する。** tagged device は通常の user identity header が付かないため、匿名 owner へ降格させない。将来扱う場合は明示的な app capability / service 認可契約を追加する。
5. **local process の信頼も記録する。** loopback は同一ホスト上の process による header 偽装を防ぐ境界ではない。初期は管理下ホストを前提とし、multi-user ホスト対応には listener 分離・OS 権限・認証済み local channel 等を別途評価する。
6. **browser 防御を維持する。** 同一 origin、CSRF 防御、body / header / connection 上限、CSP、固定 asset を扱う。provider の入力・応答を HTML として無検証で実行しない。
7. **権限変更を反映する。** receipt 照会や SSE 再接続も再認可し、利用者・workspace のアクセス失効を検証する。remote MCP を公開する場合も同じ認証・認可・監査境界に置く。

証明書検証を無効にせず、server URL と identity の変更を接続先切替として扱う。必要な tailnet policy は最小範囲とし、Serve の設定・HTTPS hostname・プロセスの信頼条件を deployment 時に検証する。

## 10. 通知・常駐・可用性

iOS の background suspend を前提に、永続的な foreground socket や終了 callback の受信を保証に使わない。app 内通知と復帰時の同期を初期必須とする。

ロック中への push は任意の後続機能。Apple の Web Push は APNs を利用するため、tailnet だけで完結する通信とは別に同意・設定を扱う。payload に prompt / command / credential を入れず、必要最小限の通知から tailnet 内で詳細を取得する。push のために Funnel を有効化しない。通知到達を承認や完了の正しさの条件にしない。

ホストは foreground CLI と常駐 service mode を区別し、macOS / Linux ごとの起動・再起動・signal・排他・ログ方針を用意する。iPhone 切断中も run は継続するが、ホストの sleep / power off / network outage を Tailscale が解消するとは扱わない。接続不能時は最終観測と不明状態を表示し、再起動時は未確定 effect の自動再実行をしない。

## 11. 公式ライブラリと不足機能の扱い

| 必要機能 | 第一候補 | 足りない場合の実装・検証 |
| --- | --- | --- |
| task、timer、queue、HTTP(S)、socket | `moonbitlang/async` の対応 package | streaming、cancel、TLS、proxy、OS ごとの挙動を固定版で検証する |
| filesystem / sync / lock | 公式 async FS | dirfd 相対操作、nofollow、同一性確認、親 directory sync などの不足だけを薄い OS primitive として補う |
| process / pipe / stdio | 公式 async process / pipe / stdio | process group、子孫終了、TERM から強制終了への移行、出力上限、終了待機を監督層に追加する |
| 正規表現・検索 | 公式 regexp と bounded traversal | JS regexp との差分を fixture 化する。停止できない CPU 処理は native worker へ隔離し、入力・memory・時間を制限する |
| glob | 公式 API を先に調査 | 現行 `path.matchesGlob` の必要な互換範囲を定義し、不足 matcher を MoonBit で補う。安全な探索とは分離する |
| CLI / JSON / encoding / property tests | 公式 core 等 | 利用する公開 API と推移的依存を固定する。不要な framework は作らない |
| iOS・browser・資格情報の OS 接続 | 公式 API + 最小 adapter | 未提供の部分は dsh / gpui 内部で実装し、OS handle と秘密情報を portable 層に漏らさない |

`WorkspaceFs`、`SnapshotStore`、`ProcessSupervisor`、bounded grep worker は内部候補名であり、既存ライブラリ名ではない。まず利用箇所と契約を dsh 内で成立させ、汎用部分だけを後から公式への還元または独立化の対象にする。

公式 API に fsync / lock / HTTP がないという前提で再実装しない。`moon ide doc` と固定版 source で不足を確認してから補う。協調的 async の timeout だけで長い同期 regex を強制中断できるとは仮定しない。worker の資源制限が実現できない platform では、受入を満たすまで当該機能を対応済みにしない。

## 12. 互換性と段階的な置換

最初は既存 Node 経路を比較用に残し、typed core / native adapter を一経路ずつ接続する。比較用 fixture に必要な旧実行系と、利用者に必須の runtime を区別し、最終的に Node なしの build / 実行 / 主要 test / 配布を独立 CI で示す。

既存 `dsh.mbt-session-v1` の読込と Session v4 の read-only import の意味を維持する。初期 native storage は既存 writer lock と相互排他にし、Node / native の二重 writer を拒否する。片側だけ advisory lock に切り替えない。

remote command receipt を導入する際は、状態と receipt が一緒に確定する永続契約を設計する。別々の JSON file を順に rename するだけで atomic transaction とみなさない。単一 envelope / journal 等を比較し、format 変更が必要なら version と明示 migration を定める。旧 reader に新しい receipt を黙って捨てさせず、対応しない writer は拒否する。既存履歴の backup / recovery と旧状態の受入を検証する。

[PR #9](https://github.com/f4ah6o/dsh.mbt/pull/9) の認証 semantics は別の機能提案として維持する。実装時の HTTPS、callback、browser launch、credential persistence は native 境界へ接続し、新しい Node host を増築しない。provider token は実行ホストに留め、client・session export・tool environment・診断ログへ混入させない。認証機能を本提案で実装済みとは扱わない。

Node を必須とする plugin 互換や public remote hosting を、この移行のために導入しない。既存提案の該当項目は別判断とし、今回そのファイルを編集・close しない。

## 13. 実装ロードマップ

暦日や対応済み宣言ではなく、依存関係と検証可能な gate で進める。各段階で小さな縦断実装を作り、全型・全 abstraction の完成を待ってから初めて実行する計画にはしない。

| 段階 | 主な作業・依存 | 到達点と gate |
| --- | --- | --- |
| M0: 契約・toolchain | baseline fixture、公式依存、guide、対象 OS / browser を固定。FS / process primitive と iOS 組込みの spike を開始 | 固定 compiler で使える機能、不足、platform 別リスクを実測で列挙。未確認を対応済みにしない |
| M1: typed kernel / API | ID、状態、command、event、effect、error と互換 adapter。M0 の挙動を維持 | 同じ契約テストが通り、内部 String / Json 往復を境界へ集約。`.mbti` をレビュー |
| M2: 共通 client と決定的検証 | protocol、presentation、仮想時刻、fake I/O、送信・接続・再同期 state machine。M1 の最小経路に接続 | 切断、完了順序、重複、保存失敗を network なしで再現。native / browser 用共通 package を検証 |
| M3: native の縦断実装 | 公式 async、WorkspaceFs、storage、process 監督、provider、6 tools、CLI。安全な primitive を先に成立させる | native だけで会話・承認・tool・保存・復元が完結。retry / pool / cancel / crash の保証を維持 |
| M4: tailnet service / remote | M2 / M3 を結合。常駐、認証・認可、command receipt の durable 記録、snapshot + SSE、HTTP / MCP carrier | iPhone から依頼・承認・結果確認。切断中に run が継続し、二重受付なく復帰。Serve 経由の負荷・拒否試験 |
| M5: PWA の日常利用品質 | 共通 client と gpui / DOM adapter、manifest / asset policy、下書き・選択復元、IME・VoiceOver | ホーム画面から使え、実機の lock / kill / Wi-Fi・cellular / tailnet 再接続試験を満たす |
| M6: Node 撤去・配布 | `.mbtx` 自動化、主要 test の MoonBit 化、対象 package selector、OS 別配布・service 手順 | Node / npm なしの clean 環境で build・実行・主要回帰検証が成功。残る OS / TLS 依存を明示 |
| M7: iOS native 正式経路 | M0 の spike を拡張し、共通 client + gpui host を接続。必要な OS 連携を追加 | Simulator と実機で共通 state machine、IME、選択、accessibility、復帰、tailnet 認証を検証 |

proof・coverage・mutation・performance の計測は各段階で実施する。M7 は PWA を失敗扱いする段階ではなく、OS 統合を深める別の提供形態。macOS / Linux の server を先行し、Windows は早期に差分調査を行うが、検証前に機能同等と宣言しない。

## 14. 受入・回帰テスト計画

以下は後続実装で実行するテストであり、この文書追加による PASS ではない。

| ID | 対象・条件 | 合格条件 |
| --- | --- | --- |
| A01 | typed kernel の操作列 | 拒否操作で部分更新がなく、stale / duplicate completion が状態を進めない |
| A02 | provider fixture / 任意 chunk・UTF-8 / EOF | 検証済み delta だけが反映され、final と一致し、不完全な tool を実行しない |
| A03 | retry / backoff / checkpoint failure | durable 順序と既存 retry 方針を保持し、不正な再送や tool の重複を発生させない |
| A04 | read pool の完了順置換 / barrier | 実行並列性を保ちつつ tool result と model context が call 順で確定する |
| A05 | symlink / ancestor 差替え / file 競合 / 出力上限 | workspace・protected data 境界と競合検出を破らない |
| A06 | snapshot 各段階の failure / process crash / 二重起動 | 部分保存を採用せず、二重 writer と不確定 effect の自動再実行を防ぐ |
| A07 | shell / grep timeout・cancel / 子孫・pipe | 未終了 process / worker / pipe を残さず、時間・memory・出力上限を実測する |
| A08 | 送信直後・受理後応答前の切断 / 再起動 | 同一 command の結果照会ができ、receipt と状態が一緒に確定し、暗黙に再実行しない |
| A09 | 別端末で承認解決 / 古い revision / ID 再利用 | 古い承認や異なる payload を拒否し、実行対象を取り違えない |
| A10 | snapshot / subscribe 間の更新 / gap / epoch 変更 | 更新を失わず、保持範囲外は full resync。遅い client で kernel を止めない |
| A11 | Serve / Host・Origin 偽装 / missing identity / 利用者失効 | 不正な接続・操作・購読を拒否し、Funnel・LAN bind・TLS 検証無効化を必要としない |
| A12 | iPhone の lock / app kill / tailnet off-on / 回線切替 | run の継続、最終観測の正しい表示、復帰時同期、未確認送信の解決を実機で確認 |
| A13 | IME / software keyboard / selection / VoiceOver / resize | 誤送信・入力消失・別対象への入力・フォーカス喪失を防ぐ |
| A14 | PWA update / storage 消去 / cache / logout | asset と API データを混同せず、古い client を検出し、利用者間に下書き等を漏らさない |
| A15 | backend matrix / `.mbti` / guide automation | 共通 package の契約が対象 backend で一致し、公開 API と script の変更を検査できる |
| A16 | Node 不在 / native package / service 再起動 | Node / npm なしで主要経路が動き、実行依存と OS 別の未対応を正しく報告する |
| A17 | iOS native ABI / memory / callback / lifecycle | Simulator・実機の両方で leak・破棄後 callback・復帰時の状態破壊がない |
| A18 | property / proof / mutation / benchmark | 実行した対象・seed・仮定・結果・基準を記録し、未実行を PASS にしない |

## 15. 提案レビューと後続作業の完了条件

提案レビューで合意する事項:

- [ ] Node 不要の範囲、公式のみの追加 MoonBit 依存、OS / TLS / browser glue の扱いが明確である。
- [ ] typed kernel、client、presentation、platform の責務と、保持する外部契約が明確である。
- [ ] 接続と run の寿命、command receipt、同期 cursor、永続 transaction の設計方針が合意されている。
- [ ] Tailscale Serve・認証・認可・proxy / local process の信頼条件が合意されている。
- [ ] PWA / iOS native の順序、早期組込み検証、gpui 側の不足と依存 gate が合意されている。
- [ ] M0-M7 と A01-A18 を、既存機能の後退を検知できる小さな実装 issue / PR に分割できる。

M0 で確定する未決事項: compiler / 公式依存 pin、OS / Safari の検証版、最小 OS primitive、receipt の保持・失効と format migration、同期 endpoint / version negotiation、client のローカル保存方針、iOS ABI / event loop 接続、最初の proof 対象。

実装 PR は変更範囲、対象 command / test、PASS / FAIL / 未実行、実機と合成試験の区別、未解決事項を記録する。文書の merge は機能の受入や全ロードマップの完了を意味しない。

この proposal の変更範囲は本 Markdown 1 ファイルのみ。runtime、依存 pin、CI、他の提案、Tailscale 設定、provider 資格情報を変更しない。

## 16. 参照資料

リポジトリの現状は第2節の baseline 固定ソースを参照する。以下の公開資料は設計根拠であり、固定 compiler / OS 上での動作検証の代わりにはしない。

1. [MoonBit agent guide（固定 revision）](https://github.com/moonbitlang/moonbit-agent-guide/blob/7262fb823452c20ffb6a01d4b06f9de639e7c774/moonbit-agent-guide/SKILL.md): package、typed API、`.mbtx`、実行可能な文書、`.mbti`、tooling。
2. [MoonBit refactoring guide（固定 revision）](https://github.com/moonbitlang/moonbit-agent-guide/blob/7262fb823452c20ffb6a01d4b06f9de639e7c774/moonbit-refactoring/SKILL.md): architecture first、公開 API 最小化、views、pattern matching、functional loops。
3. [MoonBit proof guide（固定 revision）](https://github.com/moonbitlang/moonbit-agent-guide/blob/7262fb823452c20ffb6a01d4b06f9de639e7c774/moonbit-proof/SKILL.md): `.mbtp` のモデルと実装契約の接続。
4. [公式 async](https://github.com/moonbitlang/async)、[公式 FFI / backend 資料](https://docs.moonbitlang.com/en/latest/language/ffi.html): structured concurrency と OS 境界、native library 出力の制約。
5. [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)、[Tailscale identity](https://tailscale.com/docs/concepts/tailscale-identity): tailnet 公開、identity header、tagged device、proxy の信頼境界。
6. [WebKit: Home Screen Web Apps / Web Push](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)、[WebKit: Safari 26.0](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/): ホーム画面での利用と APNs、OS version による挙動差。
7. [Apple: Preparing your UI to run in the background](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background): background / foreground のライフサイクル。
8. [gpui.mbt モバイル設計（提案時の固定 revision）](https://github.com/gpui-mbt/gpui.mbt/blob/ca11e959e620d71532beab282ab4c847616e3181/issues/open/0021-mobile-foldable-adaptive-architecture-proposal.md): 表示環境・入力・surface lifetime・適応レイアウト。未実装の提案である。
