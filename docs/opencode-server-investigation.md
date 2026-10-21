# OpenCode server経由の無料モデル利用調査

## 1. 判定（2026-10-16 JST）

**公式 OpenCode 1.19.1 のセッションAPIから、`deepseek-v4.1-flash-free` と `big-pickle` の実応答・2ターン目の履歴参照に成功しました。ただし、dsh.mbt の無料モデル用アダプターを提供できる利用許可は確認できませんでした。**

接続成功は、未改変の公式OpenCodeをHTTPで操作した調査結果です。dsh.mbt自身からの会話成功、無料枠の外部harness利用許可、製品としての対応完了は意味しません。GitHub Issuesは無効（作成APIがHTTP410）だったため、本書を文書PRとして記録しています。

公式リポジトリのCollaborator `rekram1-node` は、無料枠について次のように明言しています。

> You cannot use the free tier in other harnesses

- [同発言を含む #49580 のコメント](https://github.com/anomalyco/opencode/issues/49580#issuecomment-5723289721)
- [同じCollaboratorによる #49587 の説明](https://github.com/anomalyco/opencode/issues/49587)
- [第三者アプリの利用許可を問い合わせる #49144](https://github.com/anomalyco/opencode/issues/49144)：確認時点でopen。取得できたコメントに、第三者無料利用の明示許可はありませんでした。

したがって、ユーザー指定の「利用条件への適合と実動作を確認できた場合に実装」という条件のうち、**dsh.mbtへの組み込み許可が未充足**です。無料枠をdshの推論プロバイダーとして取り出す実装は見送ります。OpenCodeが履歴・ツール・agent loopをすべて所有し、dshを単なるクライアントとする構成についても、この一般的なServer APIの公開だけで無料枠の例外許可があるとは断定しません。

既存OpenAI互換プロバイダーとChatGPT SIWCには変更を加えていません。調査時点で #66 も未マージです。

## 2. 公式仕様と利用条件

- [Server](https://docs.opencode.ai/docs/server/)：HTTPクライアントでOpenCodeを操作する公式インターフェース。Basic認証、セッション・メッセージAPI、実サーバーの `/doc` が提供されます。
- [Inference API](https://dev.opencode.ai/v2/docs/console/api/inference)：無料チャットモデルはBearerなしでも呼べると記載。一方、#66 の直接呼出実測は403。認証ヘッダーの要否と、許可されるharnessの範囲は別です。
- [モデル・無料期間・データ取扱い](https://opencode.ai/v2/docs/console/models/)：対象2モデルは期間限定無料として掲載されています。モデル掲載や価格0は、外部harnessへの利用許可を保証しません。
- [利用規約](https://opencode.ai/legal/terms-of-service)：ホスト型サービスとOSSのライセンスを区別し、アクセス制限等も規定。OSSのMITライセンスからホスト型無料推論の無制限利用権を導くことはできません。

明示的な第三者無料利用の許可が確認されるまでは、実接続に成功したことだけでこの判定を解除しません。User-Agent、認証、セッション識別、ツール構成等を偽装して無料枠の判定を通す処理は実装していません。

## 3. 実測環境・手順

- Linux x86_64、公式npm `opencode-ai@1.19.1`。[対応する公式リリース](https://github.com/anomalyco/opencode/releases/tag/v1.19.1)も確認。
- npmパッケージのintegrity：`sha512-gmRDqlvJhlcqIeVFXW+ixh87vBRCpOPZQeIryLE2Mqmy2kzLUhiy7Knd8ToWmExM0UqIKeSvt1t0cxDgkCC9vQ==`。
- dshの調査対象main：`e8c5bd0e5959b0525df3b2e0dd9908f9a6aa149b`。#66 のHEAD：`8ce280bba842459a9d26959e67de5d110cdd9972`。
- 空の検証ディレクトリと分離したXDG config/data/state/cacheを使用。プロバイダーのAPIキー・ログイン情報は引き継いでいません。
- `opencode serve --pure --hostname 127.0.0.1 --port <ephemeral>`。ランダムな `OPENCODE_SERVER_PASSWORD` を設定。共有・自動更新は無効、ツール権限は `{"*":"ask"}`。modelとsmall_modelは明示的な無料モデルを指定。
- HTTPクライアントはPython標準ライブラリ。ローカルBasic認証以外にOpenCodeを名乗る独自ヘッダーは追加せず、推論先との通信は公式バイナリーに任せています。
- 実モデル検証は2026-10-15 21:23 UTC頃（2026-10-16 06:23 JST頃）。合成文字列のみ送信。応答のtool partは0件でした。
- 全サーバープロセスは検証後に終了済み（SIGTERM、終了値 -15）。常駐ジョブは残していません。

各モデルで `POST /session` → `POST /session/:id/message` ×2 → `GET /session/:id/message` を実行。メッセージ送信bodyは次の形式です（OpenAI Chat Completionsではありません）。

```json
{
  "model": {
    "providerID": "opencode",
    "modelID": "deepseek-v4.1-flash-free"
  },
  "agent": "build",
  "parts": [{"type": "text", "text": "<synthetic prompt>"}]
}
```

1ターン目で `DSH_CANARY_7619` を伝えて `DSH_OK` を要求。2ターン目は同じセッションに「前のトークンだけ」を質問し、履歴の再送は行いませんでした。

| 対象 | 1ターン目 | 2ターン目のtext | 判定 |
| --- | --- | --- | --- |
| deepseek-v4.1-flash-free | HTTP200 / DSH_OK | DSH_CANARY_7619 | 応答・履歴参照 PASS、完全一致 PASS |
| big-pickle | HTTP200 / DSH_OK | &lt;/think&gt;DSH_CANARY_7619 | 応答・履歴参照 PASS、2ターン目の完全一致 FAIL |

双方とも `info.role=assistant`、要求したprovider/model ID、`finish=stop`、`info.error`なしを確認。履歴APIはuser/assistant/user/assistantの4メッセージを返しました。Big Pickleの余分な文字列は観測されたモデル出力で、クライアント側で削除して成功扱いにはしていません。

## 4. プロトコル・認証・接続の検証

実行対象は調査環境内の一時的なHTTPプローブ `python3 opencode-probe/probe.py` と、推論を発生させないローカルプローブ `python3 opencode-probe/local_protocol.py`。これらの一時プローブはリポジトリには追加していません。以下は公式サーバー単体の実測であり、dshアダプターのテストではありません。

| 対象 | 観測 | 結果 |
| --- | --- | --- |
| バージョン・OpenAPI | healthに1.19.1、/docにOpenAPI 3.1.0 | PASS |
| Basic正規認証 | health/session/messageにアクセス可能 | PASS |
| 認証なし | healthとsession作成が401 | PASS |
| 間違ったBasicパスワード | healthが401 | PASS |
| 無効なsession作成body | titleに数値を渡すと400 | PASS |
| 無効なmessage body | partsに数値を渡すと400 | PASS |
| 存在しないsession履歴 | 404 | PASS |
| 保存・再起動 | noReply=trueで保存した合成userメッセージがサーバー再起動後も同一 | PASS（推論応答の再起動継続は未実行） |
| バインド | /proc/net/tcpのLISTENが127.0.0.1、同ポートの非loopback LISTENなし | PASS |
| 非loopbackからの到達性 | ローカル非loopbackアドレスへの接続はerrno101 Network is unreachable | 未検証（環境制限。接続拒否の証明ではない） |
| /providerのJSON取得 | HTTP200だがHTML応答 | FAIL（JSON catalogueとして利用不可） |
| 新 /api/sessionの作成・prompt受理 | 200、user入力は記録された | PASS（推論成功を意味しない） |
| 新 /api/session/:id/wait | 503 ServiceUnavailableError / Session wait is not available yet | FAIL（この版では未提供と応答） |
| 新APIでのモデル応答完了 | 上記503のため継続を打ち切り、interruptを実行 | 未検証 |

`/doc`には旧 `/session` と新 `/api/session` の両方があります。公開Web仕様とリリースの仕様にも差があるため、版を固定し、HTTP200だけで成功とみなさずJSON型と完了状態を検証する必要があります。新APIの503は無料枠の利用拒否を示す証拠ではありません。

調査の初回では `/provider` のHTMLをJSON objectとして扱ってプローブが停止しました。型を確認して記録するよう修正し再実行済み。非loopback検査の初回もerrno101で停止したため、後続の検査を妨げないよう記録方式を修正しています。この2件をOpenCode推論の失敗とは扱っていません。

今回の変更は本調査文書のみです。ローカルでのdshビルド・単体テスト、独立レビューは**未実行**です。[文書PR #67のCI](https://github.com/f4ah6o/dsh.mbt/pull/67/checks)は別途参照してください。#66の既存PASS結果を今回の新実装のPASSとして流用していません。

## 5. 条件を満たせた場合の最小アダプターの範囲（未実装）

1. OpenAI互換とは別のプロトコル・設定を用意し、OpenCode session IDとdshの会話IDを明示的に対応付ける。OpenCodeが履歴・agent loop・ツール実行を所有する委譲と、dshのLLMプロバイダーを混同しない。dshのtool schemaを黙って無視したり、OpenCodeのtool partをdshで再実行したりしない。
2. 同じ会話には新しいuser入力だけを送り、同時送信を直列化する。履歴全体の毎回再送、404からの無断session再作成、timeout後の非冪等POSTの自動再送は行わない。fork/import/cancel/restart時の対応関係を検証する。
3. 応答はassistantのtext partと完了状態を確認。reasoning・tool part・エラーを通常の回答に混ぜない。HTTPエラー、HTTP200中の `info.error`、空応答、型不正、許可待ち、timeoutを区別し、401/403から認証方式やモデルを切り替えない。
4. 最初は固定したliteral loopback originだけを受け付け、remote origin、userinfo、query/fragment、制御文字、redirectを拒否する。Basic専用の秘密を用い、OpenAIキーやSIWCトークンを流用しない。リクエスト・応答サイズと時間に上限を置き、秘密をログに残さない。
5. 導入条件は、dsh経由の具体的な使い方についての許可確認、バージョン固定した実サーバーE2E、上記エラー・認証・接続先制限のfixture、既存プロバイダー/SIWCの回帰確認。現状、これらのdsh実装テストは未実行。

## 6. 正当に利用できる代替方式

| 方式 | dshとの関係・必要条件 | 今回の実会話 |
| --- | --- | --- |
| OpenCode Consoleの有料API | 公式モデル資料は他coding agentでの利用も案内。既存OpenAI互換経路＋本人のAPIキーを使う。無料モデルIDを有料利用の代替として流用しない | 未実行（キーを使用していない） |
| OpenCode Go / Go Plus | [公式Go資料](https://opencode.ai/v2/docs/console/go/)が他coding agentを対象と明記。独自User-Agentと安定した会話IDが必要。サブスク加入が必要で、対象モデル・上限も別 | 未実行 |
| 自分のローカルOllama | [公式OpenAI互換API](https://docs.ollama.com/api/openai-compatibility)を使う。#66の明示的なno-auth経路が候補。ハードウェア・モデルライセンス・tool callingの適合性を確認 | 未実行 |
| OpenCode公式クライアントで無料モデルを使う | OpenCode側の利用として継続。dshの対応機能としては提供しない | serve単体は上記2モデルで成功、公式TUI/Desktop操作は未実行 |
| OpenCode serverを有料/BYOKモデルで使う | モデル条件に従い、別プロトコルの委譲アダプターとして将来検証可能。無料枠の代替権利を生まない | 未実行 |

Go資料にはupstream DeepSeek Harnessのsession header不足も掲載されています。これはMoonBit版dsh.mbtの対応済みを意味しません。調査対象mainの `runtime/` と `provider/` では `User-Agent` / `x-opencode-session` によるGo向け識別実装を確認できませんでした。Go対応を進めるなら、dsh自身を正直に識別し、親・子・補助リクエストそれぞれの実際の会話IDを一貫して伝える別タスクが必要です。

**現時点の実装判断：無料OpenCode serverアダプターは保留。次の具体的な候補は既存経路での有料Console/BYOK、または明示的なGo対応です。実会話成功の事実と、dsh製品への組み込み許可・対応完了を分けて追跡します。**
