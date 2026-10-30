# SafeRoot の bounded byte 読取を提供する

Status: open
Model: unknown
Created: 2026-10-30
Updated: 2026-10-30
Branch: refactor/20261030-bounded-byte-read

## 概要

SafeRoot でファイルの実 bytes を制限付きで読み、version を検証する内部 API を追加する。

## 背景

[archive object codec #83](https://github.com/f4ah6o/dsh.mbt/pull/83) は String を UTF-8 再符号化した内容だけを検証する。既存 read_text は BOM を解釈し、保存された bytes の同一性検証には使えない。

## 問題

将来の archive object は保存済みの bytes をそのまま hash と照合する必要があるが、text decode を通すと入力 bytes を失い得る。

## 目標

既存の path 防御、サイズと version 検証を維持し、バイナリを含む元 bytes をそのまま取得する。

## 対象外

archive の保存・採用、v2 format、wire API、quota、既存 text 操作の挙動変更。

## 提案する方針

既存 SafeRoot の regular file 読取と before/after version・mapping の確認を共有する。read_text は同じ byte 読取の後に従来どおり NUL 拒否と UTF-8 decode を行う。権限、上限、エラー挙動を維持する。

## 受け入れ条件

- [ ] BOM、NUL、不正 UTF-8 を含む元 bytes と version をそのまま返す。
- [ ] サイズ超過と symlink を拒否し、読取中変更を検出する既存 version 検査を維持する。
- [ ] 既存 read_text の decode、エラーと公開挙動に退行がない。

## テスト計画

- native SafeRoot fixtures の bytes/text 境界と既存 safety tests を実行する。
- 独立レビューと format/check、CI を実施する。

## リスク

bytes API 自体は hash の確認や認可を行わない。読み取り時の version と path mapping の保証を弱めない。

## 変更履歴

`CHANGES.md` impact: no

## 注記

保存された object の byte-level 検証を可能にする前提。storage integration、quota、容量改善は含まない。

### 2026-10-30 実装・検証記録

実装: gpt-6-luna / max。独立レビュー: gpt-6.1-sol / xhigh。native SafeRoot focused tests 3/3 PASS、native check と format PASS。raw BOM/NUL/invalid UTF-8、size、symlink、text の BOM 保持を確認。読取中の変更を直接発生させる fixture は未実施で、既存 before/after version 検査を維持したことをレビューした。実装者の以前の BOM 除去という仮説は誤りで、現行 decoder は U+FEFF を保持する。
