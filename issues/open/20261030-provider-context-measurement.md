# provider request のサイズを dispatch 前に測定する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: feat/20261030-provider-context-measurement

## 概要

engine が provider effect に結び付けた request projection を、read-only で有界に測定する API を追加する。

## 背景

長い会話の次の段階には provider に送る現在の request の大きさを観測する方法が要る。request は system prompt、message projection、tool schema から成るため、tool result の code point 数だけでは全体の大きさを把握できない。一方、provider と model ごとの正確な tokenizer はこの engine にない。

## 問題

request projection 全体の size を測る API がなく、後続の provider-specific budget を検討するための model-independent な観測値も得られない。測定のために effect dispatch queue を drain したり session state を変更したりすると、実際の実行動作を変えてしまう。

## 目標

active provider effect に保持された engine request を読み取り、serialized request / messages / tool schemas の UTF-8 byte 数、system prompt の UTF-8 byte 数と Unicode code point 数、message 数と tool 数を明示した単位で返す。queue drain 前後で同じ request を測れるようにする。

## 対象外

正確な token meter、provider context window の保証、admission budget、compaction trigger、summary 生成、live history の縮約、durable session capacity の増加は対象外。測定値を token 数や provider が受け入れる上限として扱わない。

## 提案する方針

`start_step` が作る request と active provider effect の相関を使い、Engine の read-only query から同じ request projection を取り出す。JSON size は巨大な serialize / encode allocation を先に行わない有界 walk で数える。serialized component は 16 MiB、nesting は 128 levels、訪問する JSON value は 16,777,216 個までとし、範囲外・malformed shape は状態を変えずエラーにする。API と docs で byte、code point、件数を区別し、request が provider-specific wire transformation 前の engine representation であることを説明する。

## 受け入れ条件

- [ ] 測定は `start_step` が dispatch する正確な engine request projection と、messages および tool schemas を反映する。
- [ ] query は snapshot と queued effects を変更せず、host が dispatch queue を drain した前後で動作する。
- [ ] active request が無い場合は absent を返し、malformed または bound 超過の shape は mutation なしで失敗する。
- [ ] docs は測定単位と上限を説明し、token 数や model context-window 保証を主張しない。

## テスト計画

- Unicode byte/code point、message/tool schema accounting、exact request equality、queue 非 drain、missing request、malformed shape、および 16 MiB 境界を engine tests で確認する。
- API wrapper test で native in-process query 後も queued effects が保持されることを確認する。
- engine/API package test と check、format、portable/native matrix、および exact-HEAD independent review を行う。

## リスク

これは provider-specific wire transformation 前の engine request size であり、provider が実際に受け取る bytes や token 数を表す保証はない。Unicode byte/code point と tokenization は異なる単位である。bound を超える request は測定を返さない。最新 tool result が session limit を越えた後に閉じる既存の capacity 挙動もこの increment では変わらない。

## 変更履歴

`CHANGES.md` impact: yes

項目案：

- active provider request の bounded size measurement を追加する。

## 注記

最新 tool-result capacity gap は別途 open のまま残る。over-capacity completion は現在 `session_capacity` で turn を閉じる。既存 v2 archive は commit 済みの regular Read result と direct pruning event を要するため、limit を越える completion 自体を救えない。後続では active-result summary/archive semantics、call/effect correlation の保持、object と compact projection の atomic commit、restore/no-replay test を設計し、provider-specific budget input と finite archive quota も定義する必要がある。これらを満たす前に long-session support を主張しない。
