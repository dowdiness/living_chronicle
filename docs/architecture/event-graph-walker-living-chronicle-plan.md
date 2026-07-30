# Living Chronicle architecture plan

調査日: 2026-07-30  
対象:

- Event Graph Walker `v0.6.0`, commit [`c522b536`](https://github.com/dowdiness/event-graph-walker/commit/c522b536f481da6e7d7be16198c9503c83d41f6b)
- `dowdiness/incr` typed-spreadsheet / `incr_tea`, commit `7a336e903413eee02a6043177765088e3633927f`
- `living_chronicle` 現在の空の MoonBit scaffold

実行確認:

- Event Graph Walker: `moon check --target all --deny-warn` 成功
- Event Graph Walker: `moon test` **811/811 passed**
- 公開 API は generated `.mbti` を正とした
- GitHub open issue は 2026-07-30 時点で 8 件

> 用語上の注意: 本文では、プレイヤー投稿の原本として信頼できる状態を「source-of-record」、世界の正史を「canonical」、表示用に再計算できる状態を「derived projection」と呼ぶ。CRDT に入っていること自体は、ゲーム上 canonical であることを意味しない。

---

## 1. 現在の Event Graph Walker の能力

### 1.1 公開 API

| 能力 | 判定 | 現行 API と根拠 |
|---|---|---|
| movable tree | 利用可 | `TreeState` / `container.Document` の `create_node(_after)`, `move_node(_before/_after)`, `delete_node`, `children`, `parent`, `is_alive`。[`container/pkg.generated.mbti#L31-L57`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/container/pkg.generated.mbti#L31-L57) |
| text | 利用可 | `TextState::insert/delete/delete_range/replace_range` と `TextView`。[`text/pkg.generated.mbti#L73-L100`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/text/pkg.generated.mbti#L73-L100) |
| block text | 利用可 | `container.Document` が tree node ごとに `insert_text/delete_text/replace_text/get_text/text_len` を持つ。独立した public `BlockText` 型ではない。 |
| properties | 利用可 | tree/container の `get_property` / `set_property`。値は文字列。atomic register として使える。 |
| transaction | 限定 | `Document::transaction` は undo grouping。**ロールバック可能な DB transaction ではない**。typed-spreadsheet ADR も commit boundary としての利用を明示的に棄却している。[`typed-spreadsheet EGW ADR`](https://github.com/dowdiness/incr/blob/7a336e903413eee02a6043177765088e3633927f/docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md#L140-L163) |
| undo / redo | 利用可 | `undo` package、`TextState::*_and_record`、container の `undo/redo/can_undo/can_redo`。local compensating edit であり、canonical decision の取消しではない。 |
| history | 利用可 | `CausalSnapshot::op_count/frontier/entry/children_count`。ただし snapshot は live graph の alias で frozen copy ではない。[`history/snapshot.mbt#L1-L56`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/history/snapshot.mbt#L1-L56) |
| checkout | 限定 | public には `TextState::checkout(Version) -> TextView` の read-only historical view がある。container/tree の public historical checkout と writable branch はない。 |
| sync message | 利用可 | façade ごとの opaque `SyncMessage`。strict JSON encode/decode、`op_count`、`to_canonical_bytes`。 |
| peer sync | 利用可 | `peer_sync.State + event -> (State, Decision[])`。bootstrap、incremental、full sync、recover/escalate の deterministic core。[`peer_sync/pkg.generated.mbti#L20-L47`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/peer_sync/pkg.generated.mbti#L20-L47) |
| version | 利用可 | façade ごとの opaque `Version` と JSON codec。logical document identity ではない。 |
| operation export/apply | 限定 | public は `SyncSession::export_all/export_since/apply` の batch 単位。個別 operation の inspect/export/apply は internal。[`container/pkg.generated.mbti#L80-L84`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/container/pkg.generated.mbti#L80-L84) |
| container API | 利用可 | tree + per-node text + properties + undo + sync + causal snapshot を統合する主 façade。 |
| wire format | 利用可 | schema 1 の façade-specific strict JSON。unknown fields/version を拒否。`to_canonical_bytes` は hashing/signing 用であり、binary transport decoder ではない。[`container/sync_protocol.mbt#L1340-L1419`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/container/sync_protocol.mbt#L1340-L1419) |
| resource limits | 利用可 | default 16 MiB encoded、100,000 decoded ops、10,000 pending、256 parents/op。[`sync/types.mbt#L50-L105`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/sync/types.mbt#L50-L105) |

### 1.2 正しさと wire semantics

- exact duplicate は idempotent に扱われる。
- stable identity `(replica_id, sequence)` が同じで payload/parents が違う場合は `ConflictingIdentity`。
- dependency-valid でない operation は document-local pending queue に入る。
- strict decode、dependency ordering、resource preflight 後に state を変更する failure-atomic remote admission が実装されている。
- UTF-16 surrogate pair 問題は現行コードでは修正済み。local insert は code point 単位であり、remote malformed content も検証する。[`internal/document/document.mbt#L134-L280`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/internal/document/document.mbt#L134-L280)
- issue #31 は open のままだが、回帰試験まで現行 tree に存在する。[`unicode_safety_wbtest.mbt`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/internal/document/unicode_safety_wbtest.mbt)

### 1.3 現行ベンチマーク

同一環境の release wasm-gc 比較値:

| workload | 1k | 10k | 評価 |
|---|---:|---:|---|
| sequential block text | 67.20 ms | 11.25 s | 約167倍。blocking performance investigation |
| sequential tree | 54.93 ms | 6.16 s | 約112倍 |
| reverse causal batch | 31.12 ms | 419.74 ms | PR #70 で改善 |

prebuilt 10k document への 1 public operation は JS で `insert_text` 2.41 ms、`create_node` 2.43 ms。これは一操作の応答性であり、history growth の線形性を証明しない。[`docs/BENCHMARKS.md#L65-L126`](https://github.com/dowdiness/event-graph-walker/blob/c522b536f481da6e7d7be16198c9503c83d41f6b/docs/BENCHMARKS.md#L65-L126)

### 1.4 open issue

| issue | 本計画での解釈 |
|---|---|
| [#73 superlinear insertion](https://github.com/dowdiness/event-graph-walker/issues/73) | Phase 0 blocker。text-heavy incident を避け、測定する。 |
| [#72 application adapter boundary](https://github.com/dowdiness/event-graph-walker/issues/72) | Living Chronicle は typed-spreadsheet に続く第2 driver。adapter-local receipt/impact の実測材料を提供する。 |
| [#51 RLE properties](https://github.com/dowdiness/event-graph-walker/issues/51) | hardening。 |
| [#49 TreeState properties](https://github.com/dowdiness/event-graph-walker/issues/49) | move/delete を使う本ゲームには重要。 |
| [#48 UndoManager model properties](https://github.com/dowdiness/event-graph-walker/issues/48) | draft/editor UX の hardening。 |
| [#46 checkout/merge properties](https://github.com/dowdiness/event-graph-walker/issues/46) | deterministic history/replay に重要。 |
| [#44 package publish](https://github.com/dowdiness/event-graph-walker/issues/44) | issue 内容は 0.3.0 時点で古い。0.6.0 の registry resolution は first PR で実確認する。 |
| [#31 surrogate pair](https://github.com/dowdiness/event-graph-walker/issues/31) | 現行コードでは修正済み。issue hygiene の問題であり current blocker ではない。 |

---

## 2. このゲームに適している点

1. **非同期共同性**: operation と causal DAG が、同時接続ではなく過去・未来の参加者を共同編集者にできる。
2. **append-oriented contribution**: contribution を sibling node として追加すれば、多数参加者が同じ本文を奪い合わない。
3. **tree + reference graph の二層**: tree は containment/order、properties に stable ID reference を置けば arbitrary graph を別 projection で構築できる。
4. **read-only history**: `CausalSnapshot` は「どの replica operation がどの親を持つか」を UI に出す材料になる。`agent` は端末 replica provenance であり player author ではない。author attribution は Contribution/audit model から得る。
5. **document-level partial loading と相性がよい**: EGW 自体は subtree partial replication を持たないが、IncidentDocument を小さく分割すれば購読単位を作れる。
6. **peer-sync が pure reducer**: Functional Core / Imperative Shell と一致する。
7. **typed-spreadsheet の先例**: closure-free command、EGW を先に更新してから一つの projection path を通す設計が既に実証されている。

ゲームとしての強みと技術基盤としての強みは別である。CRDT は投稿が失われないことを保証できるが、「面白い展開」「妥当な証拠」「一意資源の勝者」は保証しない。

---

## 3. 現時点での blocking issue

### P0: 公開前に解く

1. **Repo/runtime 不在**: Repo、DocumentHandle、storage/network adapter、multi-document routing がない。
2. **durability 不在**: IndexedDB、journal、durable checkpoint、restore、schema migration がない。EGW の `CausalSnapshot` は durable snapshot ではない。
3. **security boundary**: public `SyncMessage` は opaque batch なので、サーバーが個別 domain intent を安全に認可できない。untrusted client の raw sync を canonical IncidentDocument へ直接 apply してはならない。
4. **transaction 誤解**: `Document::transaction` は undo grouping で rollback transaction ではない。
5. **true compaction 不在**: external journal は checkpoint 後に削除できるが、`export_all` 内の EGW history/tombstone を縮める public compaction はない。
6. **hard deletion 不可**: redacted text は CRDT history に残る。secret/PII を replicated CRDT に保存しない。法的消去は fresh document rematerialization と old blob destruction が必要。
7. **performance gate**: 10k sequential text/tree growth はそのまま大規模 IncidentDocument に採用できない。
8. **restore identity test**: full JSON を同じ replica ID の新しい `Document` へ apply し、その後の local sequence が安全に継続することを application-level test で固定する必要がある。

### P1: pilot 前

- reconnect/retry/batching/compression/backpressure/slow-peer/full-sync escalation
- server-side persistence と single-writer/lease
- authn/authz、rate limit、moderation audit
- schema migration と clone detection
- projection index/search/metrics/tracing/deterministic replay
- JS browser target の実測。wasm-gc のみでは公開性能を判断しない。

---

## 4. ゲームの最小コアループ

```text
3分で読める Incident hook を選ぶ
  → Action / Observation / Proposal / Connection を1件作る
  → local draft + durable outbox に保存
  → server command gateway が lifecycle/auth/rate/schema/ref を検証
  → accepted Contribution を IncidentDocument に追記
  → 後続参加者が continue / support / contradict / connect
  → steward/rule が source refs 付き ConfirmedEvent を作る
  → Scene / Resolution / Chronicle を投影
  → unresolved strand と archived event から次の Seed を作る
```

一人プレイを成立させる入口は、`continue an unfinished thread`、`add evidence`、`connect two facts`、`small character action` の4種を常に1件以上提示する。同期参加者は価値を増すが、loop の前提にしない。

### 4.1 常時稼働する content lifecycle

Incident lifecycle と popularity/activity を同じ state にしない。canonical lifecycle は `Seed→Open→Developing→Resolution→Archived→Echo`、表示上の activity は `Hot/Active/Quiet/Dormant` として別 projection にする。

| situation | policy |
|---|---|
| 自動休眠 | 一定期間 contribution がなければ `Dormant`。Incident を勝手に Resolution/Archived にしない。再投稿で Active に戻せる |
| 未完了投稿 | reply/connection/contradiction がない Contribution を `needs continuation` queue に再提示 |
| 古い事件の再発見 | Region/Character/Location を閲覧したとき関連 Archived Incident を最大3件提示。世界全体の通読を要求しない |
| archived event から派生 | `SeedProposal(source_event_ids, unresolved_strand)` を作り、承認後に新 Incident。archive 自体は書き換えない |
| NPC/system event | deterministic schedule/rule の `SystemProposal` として投入。resource outcome や canon を直接変更しない |
| AI summary | input versions/source IDs 付き derived artifact。source drift 時は stale 表示・再生成 |
| AI incident candidate | SeedProposal のみ。人間または rule gate が Open にする |
| 長期放置 branch | 削除せず `unresolved strand` として archive summary/Echo candidate に残す |
| 内容が薄い incident | fabricated resolution を作らず `Archived(Unresolved/Faded)`。再発見可能 |
| 人気集中 | featured slots、cooldown、地域/人物 diversity、`needs one contribution` slot を組み合わせる。単純 vote 順だけにしない |
| onboarding | 120語以内の local context、1つの unresolved question、1つの suggested action。全 history を読ませない |

AI、NPC、scheduler は「候補を供給する」。canonical state transition、promotion、scarce-resource outcome は authoritative rule/人間が決める。

---

## 5. データモデル

### 5.1 identity rule

- application entity ID: client-generated UUIDv7/ULID 相当。時刻/乱数 capability は shell から注入する。
- `DocumentId`: `doc-type + entity-id + incarnation`。EGW `Version` と別物。
- `ReplicaId`: installation ID + incarnation。document identity と別物。
- command `RequestId`: retry/dedup 用。operation ID と同一視しない。
- schema version、rule version、projection version を別に持つ。

### 5.2 entity matrix

`immut.` は作成後変更しない fields、`edit.` は変更可能 fields。

| entity | stable identity / ownership / document | fields・lifecycle・delete | refs・concurrency・ACL・projection |
|---|---|---|---|
| World | `WorldId`; root; WorldCatalog | immut. id/schema。終了しない。delete なし | regions/chronicles。public read、service/steward write。world map projection |
| Region | `RegionId`; World; RegionCanonDoc | immut. id/world。edit. name/state summary。retire は tombstone | locations/characters/factions/incidents。steward write。region snapshot |
| Location | `LocationId`; Region tree | immut. id/region。edit. tagged atomic register。retired | parent location、incident refs。tree move は steward only。map/index |
| Character | `CharacterId`; Region | immut. id/origin。edit. public profile/status through approved register | faction/location/event refs。players create portrayal contributions, canon state is service-owned。character page |
| Faction | `FactionId`; Region | immut. id。edit. approved profile/state。retired | members/rivals/events。steward write。relationship graph |
| Incident | `IncidentId`; Region; IncidentDoc | immut. id/seed/region。edit. hook/activity。`Seed→Open→Developing→Resolution→Archived→Echo` | locations/actors/source incident。client read、gateway write、lifecycle service-only。incident card/detail |
| Contribution | `ContributionId`; Incident; node | immut. author/type/submitted body after submit。draft は別。withdraw/redact/late states | parent contribution、refs、tags。append-only; amendment は新 node。author submit via gateway。thread projection |
| Action | Contribution variant | immut. actor/intent/stakes/body | target character/location/incident。success は authoritative rule が別 decision を出す |
| Observation | Contribution variant | immut. witness/claim/body | source/event/character refs。truth と canonicality は別 |
| Proposal | Contribution variant | immut. proposed development/body | supporting/opposing refs。accepted/rejected を上書きせず decision を追加 |
| Connection | `ConnectionId`; Incident or cross-doc edge record | immut. `from,to,relation,author`。withdraw/redact | arbitrary entity IDs。tree ではなく edge-as-node。graph projection |
| ConfirmedEvent | `ConfirmedEventId`; CanonLedgerDoc | immut. decision output、source refs、rule version。supersede のみ | contributions/characters/locations/causes。service/steward only。canonical timeline |
| Scene | `SceneId`; Incident/Chronicle | immut. source event set。edit. trusted-editor paragraphs。publish/supersede | ConfirmedEvents/contributions。大人数は paragraph node append、同じ text の直接編集を避ける。story view |
| Chronicle | `ChronicleId`; World/Region; ChronicleDoc | immut. scope。edit. ordered chapter refs。publish/new edition | scenes/events/incidents。editor only。reader projection |
| Resolution | `ResolutionId`; Incident; CanonLedgerDoc | immut. kind/outcome/source refs/rule version | closes active phase but does not delete branches。service/steward only。archive summary |
| Player | `PlayerId`; auth DB + private PlayerDoc | identity credential は CRDT 外。edit. pseudonym/preferences。account deletion policy | contributions/use notifications are derived refs。owner read/write、moderator limited。profile/my contributions |
| Role | `(PlayerId, ScopeId, RoleKind, grant-id)` | append-only grant/revoke audit | guest/contributor/steward/moderator/system。auth service authoritative。effective ACL projection |
| Vote | `VoteId` or `(poll,player)` accepted ballot ledger | append-only ballot/retraction、one-effective-vote rule | proposal/event candidate。server validates uniqueness。aggregate derived、minority/raw arguments retained |
| ModerationDecision | `DecisionId`; moderation ledger | immut. target/action/reason/rule/moderator/time。supersede/appeal | target contribution/player。moderator service only。public visibility projection + private audit |

### 5.3 tree と reference graph

**EGW tree に置くもの**:

- Region 内 location hierarchy
- Incident 内 contribution thread ownership/order
- Scene paragraph/chapter ordering
- Chronicle chapter ordering
- trash/tombstone containment

**reference graph に置くもの**:

- Character ↔ Faction、evidence supports/contradicts、Event caused_by、Contribution continued_from
- cross-document references
- Connection 自体を edge-as-node として attribution/moderation/history を保持

node move を graph relation の更新として乱用しない。document を跨ぐ move は「新 doc に reference を作成 + old placement を supersede」で表す。

---

## 6. document 分割

当初案をそのまま採用しない。

| document / store | owner | 内容 | subscription |
|---|---|---|---|
| `WorldCatalogProjection` | projection service | open/featured/archive refs、軽量 region refs | Home で常時。原本 CRDT ではなく再構築可能 index |
| `RegionCanonDocument` | steward/service replicas | locations、characters、factions、approved regional state | 現在地域のみ。client は read-only |
| `IncidentDocument` | gateway/service replicas | bounded accepted contributions、threads、connections、incident metadata | 選択中 incident のみ |
| `ContributionDraftDocument` | player/device or player account | uncommitted draft、必要なら複数端末 text CRDT | composer 時のみ。非公開 |
| `CanonLedgerDocument` | authoritative service | ConfirmedEvent、Resolution、source refs、rule version | incident/story/history 時 |
| `ChronicleDocument` | trusted editors/service | scene/chapter outline、published editions | Story view 時 |
| `PlayerPrivateDocument` | player | optional cross-device draft refs/discoveries/preferences | login player のみ。auth credential は含めない |
| `ModerationLedger` | moderation DB/event log | decisions、appeals、sensitive audit | moderator only。public CRDT にしない |

重要な修正:

- `WorldIndexDocument` は freely writable CRDT にせず、projection または server-owned document にする。
- `PlayerDocument.contributions` は原本を複製せず、ContributionId の derived index にする。
- IncidentDoc は operation budget で rotate/archive する。現時点では subtree partial replication はないため、document 境界が partial replication 境界である。
- 一つの world mega-document は禁止。

---

## 7. CRDT と authoritative rule の境界

### 7.1 state classification

| state | 保存先 | 理由 |
|---|---|---|
| player action / observation / proposal 原本 | accepted 後 Incident CRDT。送信前は private draft/outbox | source-of-record、offline merge |
| 投稿本文 | submit 後 immutable atomic property。draft/少人数 scene は block text | 大人数 character merge を避ける。typed-spreadsheet の atomic register 方針を再利用 |
| 投稿間 reference | Connection edge record in CRDT | attribution/history が必要 |
| vote | authoritative ballot ledger。aggregate は derived | one-person-one-vote、ACL、fraud control は CRDT だけでは不可 |
| trust score / computed confidence | derived service state | moderation outcomes・source quality から再計算。client write 禁止。投稿者自身の confidence 表明は immutable source field として別保存可 |
| moderation state | restricted append-only decision ledger | audit/authorization。公開 CRDT に secret reason を置かない |
| ConfirmedEvent | server-owned CanonLedger CRDT + decision audit | canonicality は authoritative rule output |
| current incident list | projection | lifecycle documents から再計算 |
| newcomer summary | versioned derived artifact | source version/projection version を持つ |
| AI text | proposal artifact または cache | approval前は canonical ではない。model/prompt/source/version を保存 |
| notification | per-user delivery DB | exactly/at-least-once delivery。CRDT 不要 |
| presence / connection state | ephemeral channel + TTL | historyへ残さない |
| reading position / UI filter | local storage、任意で private player sync | public world stateでない |
| search index | derived index | rebuildable |
| causal graph projection | derived from `CausalSnapshot`、cache 可 | raw causal historyが原本 |

### 7.2 derived を保存する判断基準

保存するのは、(a)計算が高価、(b)AI のように非決定的、(c)通知のように配達状態が必要、(d)監査上その時点の出力が必要、のいずれか。保存時は必ず `input_document_versions`, `projection_schema`, `producer`, `created_at`, `rebuildable` を付ける。安価で決定的な sort/filter/count/search facet は再計算する。

### 7.3 conflict matrix

| conflict | CRDT が決めるもの | game rule / UI が決めるもの |
|---|---|---|
| concurrent append | 両 contribution を保持・収束 | ranking、visibility、moderation |
| same text edit | sequence text を収束 | production では immutable body + amendment を採用し回避 |
| classification vs classification | property を使えば LWW 収束 | 少数意見を失わないよう classification proposal を appendし canonical decision を別に置く |
| move vs move | tree の deterministic placement | conflict badge、review、canonical placement |
| move vs delete | tree state は収束 | public projection は withdrawal/redaction を優先。move で自動復活させない |
| edit vs delete | text/history は保持し得る | deleted target は非表示。restore は権限付き明示 command |
| duplicate submit | identical op duplicate は EGW が吸収 | request ID で semantic duplicate を gateway が排除 |
| stale UI | operation は merge 可能 | command generation/base lifecycle を検証し stale rejection/reroute |
| offline after Resolution/Archive | raw op を直接 canonical doc に apply しない | `LateContribution` / Echo inbox へ route。incident を自動再開しない |
| old schema | EGW schema は strict reject | app migrator、unsupported write quarantine、client upgrade |
| scarce resource / success | 何も決めない | single authoritative transaction/lease が決める |

---

## 8. local-first runtime の設計

### 8.1 typed-spreadsheet / incr_tea から採用する形

```text
UI Msg
  -> pure plan_command
  -> closure-free StoryCommand(request_id, doc_generation, data)
  -> durable intent journal
  -> authoritative/local EGW mutation shell
  -> immutable RawDocumentSnapshot
  -> pure projection transition
  -> one Runtime::batch
  -> commit retained projection state only after success
```

根拠:

- closure-free command + `DocumentGeneration`: [`domain/command.mbt#L1-L108`](https://github.com/dowdiness/incr/blob/7a336e903413eee02a6043177765088e3633927f/examples/typed_spreadsheet_incr_tea_demo/domain/command.mbt#L1-L108)
- pure `previous + snapshot -> candidate + decisions`: [`projection.mbt#L19-L119`](https://github.com/dowdiness/incr/blob/7a336e903413eee02a6043177765088e3633927f/examples/typed_spreadsheet_incr_tea_demo/egw_adapter/core/projection.mbt#L19-L119)
- `Runtime::batch` 後のみ retained state commit: [`adapter.mbt#L274-L335`](https://github.com/dowdiness/incr/blob/7a336e903413eee02a6043177765088e3633927f/examples/typed_spreadsheet_incr_tea_demo/egw_adapter/adapter.mbt#L274-L335)
- `incr_tea.Program` の `Scope + Derived + Watch + batch`: [`incr_tea/program.mbt#L28-L178`](https://github.com/dowdiness/incr/blob/7a336e903413eee02a6043177765088e3633927f/incr_tea/program.mbt#L28-L178)

local command と remote sync は、必ず同じ merged EGW state から同じ projection path を通す。local optimistic projection を第二の authority にしない。invalid payload では last-good semantic projection と deterministic diagnostic を保持する。

### 8.2 runtime API 案

```text
Repo
  open(DocumentId, ReplicaIdentity) -> DocumentHandle
  subscribe(DocumentId) -> Subscription
  close(DocumentId)
  route(NetworkEnvelope)

DocumentHandle
  version_json() -> String
  export_full_json() -> DurableCheckpointPayload
  apply_local(StoryCommand) -> CommitReceipt
  apply_remote_json(String) -> ApplyReport
  restore(DurableCheckpoint, JournalEntry[]) -> RestoreReport

CommitReceipt
  request_id
  before_version_json
  after_version_json
  delta_sync_json
  operation_count
  touched_entity_ids (application-known conservative set)
```

`touched_entity_ids` は EGW に generic changed-entity API を要求せず、command lowering が知っている application set を返す。remote apply の impact は最初は bounded document scan/diff で正しさを優先し、第2 driver と実測が揃ってから EGW #72 の API 候補にする。

### 8.3 durable storage

`CausalSnapshot` と混同しないため、永続化用を `DurableCheckpoint` と呼ぶ。

```text
Manifest:
  document_id, document_kind, app_schema, egw_schema,
  replica_id, replica_incarnation, sync_limits,
  checkpoint_seq, encoded_checkpoint_bytes, checksum

DurableCheckpoint:
  full_sync_json = doc.sync().export_all().to_json_string()
  version_json
  journal_high_watermark

JournalEntry:
  seq, request/message id, direction, app_schema,
  sync_delta_json, before/after version, checksum
```

- restore は `Document::new_with_sync_limits(replica_id, persisted_limits)` → full JSON decode/apply → journal delta replay。
- operation count だけでなく serialized full JSON byte size を checkpoint/rotation gate にする。default 16 MiB より十分低い product cap を設け、checkpoint が receiver limit を超える前に IncidentDocument を rotate/archive する。
- duplicate replay は EGW idempotence を利用。
- local crash safety は write-ahead `CommandIntent` を IndexedDB に保存してから mutation し、delta と commit marker を同じ IndexedDB transaction で確定する。
- checkpoint commit 後に external journal を削除できるが、EGW internal history は縮まらない。
- IndexedDB adapter、compression、browser random/clock は JS/TypeScript の thin shell。MoonBit は schema、reducer、codec、replay verifier を担当。

### 8.4 replica identity と clone detection

- installation secret/ID と monotonic incarnation を IndexedDB に保存。
- `ReplicaId = installation-id:incarnation`。
- 同一 browser profile 内の concurrent tabs は BroadcastChannel/relay lease で早期検知し、一方を新 incarnation へ移す。
- profile/storage copy が双方 offline で operation を作ることは lease では予防不能な failure mode である。再接続時の `ConflictingIdentity` 検知、quarantine、operator/user-visible recovery を必須にする。
- conflict 済 raw ops の ID rewrite はせず、pending domain commands を新 replica で rebase/re-execute する。

### 8.5 network/runtime

- outer envelope に `document_id`, `message_id`, `sender_session`, `app_schema`, `payload_encoding`, `payload_json` を持たせる。EGW payload 自体には DocumentId がないため、caller-supplied `document_id` を信用しない。authenticated subscription/session が server-side で bind した document にだけ route し、canonical docs は gateway-generated deltas のみ許可する。
- relay は EGW payload を解釈しないが、ingress provider は認証済 session-to-document binding と envelope size/schema を検証する。
- subscribe/unsubscribe は document 単位。
- reconnect は peer version exchange → incremental、missing dependency/recoverable failure → full sync。
- batch は size/time 上限でまとめる。storage/network compression は Brotli/gzip。canonical bytes は compression transport ではない。
- peer ごとの outbound queue を bounded にし、slow peer には delta を無限保持せず `ResyncRequired` を送る。
- presence は別 ephemeral envelope + TTL。

### 8.6 component boundaries

| component | responsibility / authority | failure, retry, idempotency, trust | language |
|---|---|---|---|
| event-graph-walker core | per-document operation/history/merge | invalid message atomic reject、duplicate idempotent | MoonBit dependency |
| EGW adapter | StoryCommand lowering、snapshot、single projection path | command request ID、readback、last-good diagnostic | MoonBit |
| Repo/runtime | document handles、routing、subscriptions、sync state/effects | reducer deterministic、I/O result eventsで再試行 | MoonBit core + JS shell |
| StorageAdapter | IndexedDB / server durable records | atomic tx、checksum、journal replay | browser/server adapterは TS/JS、types/codecsは MoonBit |
| NetworkAdapter | BroadcastChannel/WebSocket、backpressure | at-least-once、message ID dedup、reconnect | TS/JS shell |
| server relay | auth済 room/doc routing、fan-out | payload opaque、bounded queue、slow-peer resync | MoonBit policy + Worker/Node TS shell |
| authoritative game service | lifecycle、resource conflict、promotion、request dedup | single writer/lease or serializable DB tx | deterministic MoonBit domain + DB/HTTP shell |
| projection/index service | catalog/search/history/use graph | versioned/rebuildable、eventual consistency | MoonBit projection core + DB index |
| frontend | TEA messages、incr projection、offline UX | local last-good、no hidden authority | MoonBit JS target + small DOM/IDB JS |
| moderation | decision audit、visibility、appeal | strong auth、no CRDT secret | MoonBit policy + DB/service shell |
| AI assistance | summary/classification/seed proposals | non-authoritative、provenance、approval | external model API shell + MoonBit validator |

---

## 9. 公開デモの UX

### 9.1 5分 onboarding

1. Home で「この都市では過去の参加者の断片が次の人の手掛かりになる」と一文で説明。
2. `2分 / 調査`, `3分 / 行動`, `3分 / つなぐ` の3入口。
3. Incident card には必要な背景を120語以内、unresolved hook を1つ表示。
4. Composer は type を選び、テンプレートを埋め、preview、submit。
5. 完了画面で「あなたの断片はこの thread に追加された」「offline queue / synced / pending review」を示す。

### 9.2 screen matrix

| screen | see / actions | read / write | local-first・offline・states |
|---|---|---|---|
| Home | city pulse、3入口、最近のecho | WorldCatalogProjection、Player summary / none | cached catalog。offline は閲覧・draft開始可。emptyはseed tour |
| Open Incidents | 5–10 cards、time/need/activity | catalog / none | stale badge付きcache。filterはlocal |
| Incident Detail | hook、participantsではなくthreads、confirmed facts、unresolved points | IncidentDoc + Region subset + CanonLedger / local draft/outbox | cached read。concurrent append はlive chips。error時 last-good |
| Contribution Composer | Action/Observation/Proposal/Connection template、refs | Incident metadata + DraftDoc / DraftDoc, CommandIntent | autosave。offline submitはQueued。schema/lifecycle stale時 reroute説明 |
| Story / Chronicle | approved scenes、source links | ChronicleDoc + CanonLedger / editor only | offline read。edition/version表示 |
| World History | timeline + causal DAG + filters | history projection、必要時 `CausalSnapshot` / none | graph incremental load。missing cold archiveを明示 |
| My Contributions | queued/published/used-in-event/continued-by | private player index + use projection / withdraw request | device cache。notificationはservice DB |
| Sync Status | docs subscribed、replica、pending、last checkpoint、last sync、duplicates/full sync | local runtime metadata / retry, export diagnostic | offlineを正常状態として表示。raw bodyはログに出さない |
| Moderation / Review | queue、source refs、decision form、appeal | restricted ledger + candidate docs / ModerationDecision, promotion command | moderator only。offline decisionは原則不可または署名済queue |

loading は skeleton + cached content、empty は次の一人用 task、error は retry と diagnostic ID、conflict は「勝敗」ではなく双方の operation と product decision を分けて表示する。

### 9.3 CRDT strength demo

| scenario | UI explanation |
|---|---|
| 2人がofflineで別投稿 | A/B lane に `Created offline`、再接続後に2つが thread へ合流。消えた投稿ゼロを数える |
| 異なる観点 | same incident に Action/Observation lanes。ConfirmedEvent とは色を分ける |
| same Scene parallel append | character text の同時上書きではなく paragraph node を別々に追加し、両段落を保持 |
| same Contribution classification | technical LWW demo は winner と causal alternatives を表示。production は classification proposals を両方保持 |
| move vs move | before/after tree、deterministic placement、`review recommended` を表示 |
| move vs delete | CRDT result と「public visibilityはdelete policy優先」を並記 |
| archive後 offline復帰 | `Archived; contribution preserved as Late/Echo candidate`。archiveを再開しない |
| different delivery order | 3 replica の delivery order と最終 projection hash 一致を可視化 |
| causal formation | node/edge を選ぶと parent ops、replica provenance、Contribution model 上の author、derived event/scene への経路を分けて表示 |
| later reuse | My Contributions に `Used by ConfirmedEvent X`, `Continued by Y` source path を表示 |

---

## 10. MVP

### 実装する

- 一都市、3件の seeded incident（同時 active IncidentDocument は最初1件でもよい）
- Action / Observation / Proposal / Connection
- contribution thread append、continue、source refs
- contribution body は submit 後 immutable atomic property、最大280–500文字
- draft は local block text、trusted Scene sandbox で block text を利用
- in-page 2 replicas、offline toggle、reconnect、history、sync diagnostics
- IndexedDB durable outbox/checkpoint
- manual steward promotion で ConfirmedEvent 1件、manual archive、Echo seed 1件
- guest device identity + pseudonym
- auto-public は選択式/template contribution のみ。自由文は pending review で公開しない
- one Incident への operation budget と rotation

### 実装しない

- 500人が同じ Scene text を直接編集
- 自動勝敗判定、希少資源 economy、複雑な rule engine
- public voting/trust score
- AI
- cross-region world simulation
- true core-log compaction / GDPR-grade in-place erasure
- P2P mesh、voice/chat、rich presence
- arbitrary raw client SyncMessage の canonical server apply

この MVP は一人で thread を継続でき、二人なら別投稿の合流を見せ、offline/reconnect を体験できる。AI・常時 moderator がいなくても constrained input で公開可能にする。

---

## 11. 段階的ロードマップ

| phase | purpose / implementation | completion, tests, benchmark | risk / go gate |
|---|---|---|---|
| 0 Upstream gate | v0.6.0 pin、full JSON restore/continue、duplicate/permutation、JS+wasm baselines、issue triage | 811 tests + app probes、1k/10k mixed workload | same-replica restore と operation budget が通らなければ停止 |
| 1 In-page replicas | IDs、closure-free commands、Incident codec、2–3 DocumentHandle harness、single projection path | offline permutation convergence、history UI | `transaction` を rollback と誤用しない |
| 2 Durable local | memory adapter→IndexedDB、intent journal、checkpoint、replay、migration v1 | reload/crash injection/checksum/replay hash | data loss/corrupt restore があれば停止 |
| 3 Cross-tab | BroadcastChannel provider、lease/clone detection、tab subscription | duplicate/delay/drop/tab close tests | same ReplicaId fork を防げること |
| 4 Cross-device | WebSocket relay、server journal/checkpoint、auth guest token、document subscription、backpressure | 2 browser/device reconnect、5k delta/full sync | unbounded queue/raw canonical writesは禁止 |
| 5 One-city game | catalog、3 incidents、composer、continue/connect、My Contributions、sync UI | 5分 usability、一人 loop、two-player collaboration | free text publication gate |
| 6 Multi-document/archive | 5–10 incidents、Region/Canon/Chronicle docs、archive/Echo、subscription switch | many-doc restore、archive boundary、cold load | mega-doc へ戻らない |
| 7 Authority/moderation | command gateway、promotion、resolution、vote ledger、role/authz/rate limit | authorization/spam/stale/duplicate/appeal tests | service single-writer/DB tx |
| 8 AI projection | summary、unresolved extraction、classification/scene/seed proposal | provenance、approval、prompt-injection tests | AI canonical writeを技術的に不可にする |
| 9 Scale/operations | load/fault/chaos、metrics/tracing、retention/DR | staged 10/100/500 connections、1M ops across docs | SLO と cost gate を満たす |

---

## 12. テスト戦略

### CRDT / deterministic core

- property-based convergence、dependency-valid permutation、duplicate delivery
- dropped/delayed/reordered/batched messages
- 2–5 replica generated traces
- move/move、move/delete、edit/delete、classification alternatives
- stale replica、full sync escalation、pending limit
- same final projection + same canonical bytes/hash where appropriate
- causal DAG acyclic/reachable source paths

### durability/destructive

- checkpoint restore + post-restore local operation
- crash points: intent before apply、after apply before commit、checkpoint before head swap、old journal prune
- checksum failure、partial/truncated journal、duplicate journal replay
- browser reload、tab kill、quota exceeded、IndexedDB upgrade abort
- several days offline + thousands operations
- app schema N-1 migration、unsupported N+1 quarantine
- deterministic replay from command/decision log with explicit clock/ID/rule version

### authority/security

- unauthorized role/document、expired guest token、capability leak
- duplicate request ID、same vote twice、rate-limit race
- malformed JSON、unknown fields、oversize text/refs/parents
- spam bursts、many docs/peers、slow consumer
- archive after stale command、late arrival、hard-redaction rematerialization
- no PII/body in logs/traces/metrics

正常系より、壊れた delivery、crash、stale authority、malicious input を先に増やす。

---

## 13. 性能計画

現行 evidence から、最初から「1 IncidentDocument に1万 contribution」は採用しない。1 contribution の本文を sequence text にすると文字数分 operation が増えるため、immutable body は atomic property にする。

### staged scale

| stage | topology / document budget |
|---|---|
| MVP | 10 concurrent total、3 incidents、active incident ≤500 contributions / ≤20k EGW ops **かつ serialized full checkpoint が product byte cap 未満** |
| pilot | 100 connected total、10 incidents、per incident realtime ≤20、≤50k ops |
| growth | 500 connected total、50+ subscribed docs、per-doc fan-out ≤50。500-peer single room はしない |
| world history | 1M ops across many active/cold docs。client は必要 docs のみ load |
| offline | 3日 offline、5k operation delta。大きければ full checkpoint sync |

### candidate SLO（Phase 0/9 で実測後に確定）

- local contribution plan+apply p95 < 50 ms on JS target
- remote 100-op batch apply p95 < 100 ms at 20k-op incident
- warm incident switch p75 < 500 ms、cold p75 < 2 s
- 20k-op restore p95 < 2 s
- 5k-op reconnect sync p95 < 2 s（network除外/込みを分離）
- active client memory < 100 MiB mobile class
- relay queue per `(connection,doc)` bounded、overflow は resync
- checkpoint < 500 ms、projection update < 50 ms、history query < 200 ms

計測項目:

- local operation、remote apply、initial load、restore、reconnect
- memory、checkpoint/journal/storage/wire compressed/uncompressed size
- relay fan-out、queue depth、dropped→resync、slow-peer age
- checkpoint/outer-journal compaction time
- projection/index update、history query、document subscription switch
- full scan count/property reads（typed-spreadsheet baseline の pressure point）
- JS と wasm-gc の両方。UI frame timingとcore scalabilityを別に報告

---

## 14. ADR 候補

1. Multi-document, document-granularity replication を採用する
2. DurableCheckpoint + delta journal、`CausalSnapshot` は永続 snapshot ではない
3. client-generated stable entity ID
4. ReplicaId installation/incarnation と clone recovery
5. CanonicalEvent は authoritative service/steward が所有
6. source-of-record CRDT / canonical ledger / derived projection の三層
7. submitted Contribution immutable、修正は Amendment
8. moderation decision ledger と public visibility projection
9. AI output は proposal/derived のみ
10. archived doc への late operation は Late/Echo route
11. retention、external journal prune、core history rematerialization
12. partial replication は document 単位
13. presence は ephemeral TTL channel
14. role/scope based access control は CRDT 外
15. app schema migration と strict EGW schema の分離
16. atomic property body vs sequence text
17. local/remote mutation は一つの projection path
18. `Document::transaction` を rollback commit として使わない
19. payload-opaque collaboration runtime / provider / application policy の分離
20. incr projection lifecycle は `Scope + Watch + Runtime::batch`

---

## 15. 最初に作るべき具体的な issue 一覧

以下は依存順。issue 1 が最初の PR である。

### Issue 1 — Pin EGW v0.6.0 and prove restore/continue semantics

- **Goal:** current scaffold から EGW を利用し、full JSON restore とその後の local edit を固定する。
- **Motivation:** durable runtime の最重要未確認点。`to_canonical_bytes` を誤って restore format に使わない。
- **Scope:** `moon.mod` に `dowdiness/event-graph-walker@0.6.0`、root `moon.pkg` test imports、probe tests/bench。
- **Out of scope:** Repo、IndexedDB、UI。
- **Proposed API:** production public API なし。test helper `restore_container(replica_id, full_sync_json)`。
- **First PR files:** modify `moon.mod`, `moon.pkg`, `README.mbt.md`; add `egw_restore_probe_test.mbt`, `egw_convergence_probe_test.mbt`, `egw_probe_benchmark.mbt`; generate root `.mbti` only if public API changes（原則変更なし）。
- **Acceptance:** new→tree/property/text→export JSON→new same replica→apply→new local op→peer convergence。duplicate/permutation、limits、Unicode を確認。
- **Tests:** JS/wasm-gc、`moon check --target all --deny-warn`, `moon test`, targeted bench。
- **Dependencies:** none。
- **Risks:** #44 registry resolution、same replica restore semantics、benchmark host noise。

### Issue 2 — Define identities, document incarnation, and app schema envelopes

- **Goal:** `DocumentId`, entity IDs, `ReplicaId`, `RequestId`, `DocumentGeneration`, schema typesを分離。
- **Motivation:** EGW Version/incr Revision/room ID との混同を防ぐ。
- **Scope:** `domain/identity` package、validated constructors、strict JSON。
- **Out of scope:** random/clock implementation。
- **Proposed API:** `DocumentId::DocumentId`, `ReplicaIdentity::ReplicaIdentity`, `DocumentGeneration::initial/next`, `AppEnvelope::decode`。
- **Acceptance:** empty/invalid IDs reject、roundtrip、generation stale precedence。
- **Tests:** malformed/unknown field/N-1 fixtures。
- **Dependencies:** #1。
- **Risks:** public newtype API を早く固定しすぎる。

### Issue 3 — Add closure-free StoryCommand and pure admission planner

- **Goal:** Action/Observation/Proposal/Connection/Continue を値 command として表す。
- **Motivation:** write-ahead journal、retry、deterministic validation、stale screen rejection。
- **Scope:** `domain/command`, `domain/admission`; generation/base lifecycle、request ID、explicit clock/ID input。
- **Out of scope:** EGW mutation、network。
- **Proposed API:** `plan_command(WorldSnapshot, StoryCommand) -> AdmissionDecision`。
- **Acceptance:** no closure/runtime capture、all rejections structured、pure deterministic tests。
- **Tests:** stale/archive/schema/ref/length property tests。
- **Dependencies:** #2。
- **Risks:** UI precondition と authoritative precondition の混同。

### Issue 4 — Define IncidentDocument codec and bounded immutable snapshots

- **Goal:** tree/property/reference mapping を一箇所に閉じ込める。
- **Motivation:** arbitrary property keys と malformed remote payload を domain へ漏らさない。
- **Scope:** versioned tagged registers、Contribution body atomic property、Connection edge record、strict decode、last-good diagnostic core。
- **Out of scope:** generic `egw_incr`、public EGW change。
- **Proposed API:** `encode_contribution`, `decode_incident_snapshot`, `compute_incident_projection`。
- **Acceptance:** torn stateなし、invalid payload retains last-good、owned arrays only。
- **Tests:** codec fuzz、unknown version、reference validation。
- **Dependencies:** #3。
- **Risks:** property enumeration がないため bounded known-node scan が必要。

### Issue 5 — Implement DocumentHandle and one projection path

- **Goal:** local StoryCommand と remote SyncMessage を同じ projection path に統合。
- **Motivation:** typed-spreadsheet で実証済みの authority invariant。
- **Scope:** EGW mutation shell、before/after version、delta JSON、readback、`CommitReceipt`, `ApplyReport`。
- **Out of scope:** persistence I/O、network I/O。
- **Proposed API:** `DocumentHandle::apply_local`, `apply_remote_json`, `snapshot`, `export_full_json`。
- **Acceptance:** EGW first→snapshot→pure transition→`Runtime::batch`→success後のみ retained state commit。
- **Tests:** local/remote equivalent projection、projection failure retry、no rollback claim on `transaction`。
- **Dependencies:** #4。
- **Risks:** mutable Document ownership、remote impact full scan cost。

### Issue 6 — Build same-page ReplicaLab and CRDT explanation UI

- **Goal:** 2–3 replica、offline、reorder、duplicate、history をブラウザ内で操作可能にする。
- **Motivation:** core semanticsを network/storage 前に可視化・検証。
- **Scope:** `incr_tea.Program`, `Scope`, persistent `Watch`, replica lanes、delivery queue、causal graph。
- **Out of scope:** IndexedDB/WebSocket。
- **Proposed API:** `ReplicaLabEvent -> (ReplicaLabState, Effect[])`。
- **Acceptance:**全 demo scenarios のうち offline append、classification、move conflicts、permutation hash。
- **Tests:** reducer tests、DOM smoke、post-dispose dispatch false。
- **Dependencies:** #5。
- **Risks:** demo-only state が production runtime に侵入。

### Issue 7 — Specify Repo reducer and adapter capabilities

- **Goal:** multi-document state と I/O effects を Functional Core / Imperative Shell で定義。
- **Motivation:** `Repo` が直接 IndexedDB/WebSocket に依存しないようにする。
- **Scope:** `RepoState + RepoEvent -> (RepoState, RepoEffect[])`, handles/subscriptions。
- **Out of scope:** concrete browser adapter。
- **Proposed API:** `Repo::reduce`, `open/close/subscribe/route` events/effects。
- **Acceptance:** no I/O in reducer、document-granularity subscription、effect idempotency key。
- **Tests:** model-based state transitions。
- **Dependencies:** #5。
- **Risks:** async trait より event/effect が適切か API spike 必要。

### Issue 8 — Implement DurableCheckpoint, journal replay, and memory adapter

- **Goal:** storage format と crash state machine を browser-independent に固定。
- **Motivation:** IndexedDB 実装前に replay correctness を検証。
- **Scope:** checkpoint/intent/journal manifest、checksum、memory adapter、restore report。
- **Out of scope:** external journal compression、core compaction。
- **Proposed API:** `restore(checkpoint?, journal)`, `plan_checkpoint`, `verify_replay`。
- **Acceptance:** every crash cut restores last committed state、uncommitted intent policy documented、persisted sync limits と checkpoint byte cap を超える前に rotation decision。
- **Tests:** truncated/corrupt/duplicate/out-of-order journal。
- **Dependencies:** #7。
- **Risks:** app command replay と sync delta replay の順序。

### Issue 9 — Add IndexedDB crash-safe StorageAdapter

- **Goal:** reload 後に document/outbox を復元。
- **Motivation:** public local-first の最低条件。
- **Scope:** JS/TS IDB adapter、atomic head swap、quota errors、migration v1。
- **Out of scope:** server DB。
- **Proposed API:** shell capability `load_manifest/append_intent/commit_delta/write_checkpoint/prune`。
- **Acceptance:** browser kill at injected cut points、upgrade abort recovery、offline queue persistence。
- **Tests:** Playwright reload/multi-tab/quota simulation。
- **Dependencies:** #8。
- **Risks:** MoonBit JS FFI、transaction lifetime、storage eviction。

### Issue 10 — Add BroadcastChannel sync and replica clone lease

- **Goal:** tab 間同期と同一 ReplicaId fork 防止。
- **Motivation:**別タブは最初の実運用的 concurrency failure。
- **Scope:** provider、lease/heartbeat、新 incarnation、resync。
- **Out of scope:** internet transport。
- **Proposed API:** `TransportProvider`, `CloneDetected`, `ReincarnateReplica` effects。
- **Acceptance:** same-profile online tabs are fenced or reincarnated; leader death takeover。copied offline profile は予防不能と明記し、reconnect conflict quarantine/rebase を検証。
- **Tests:** duplicate/delay/tab crash/storage clone。
- **Dependencies:** #9。
- **Risks:** split brain、background tab timer throttling。

### Issue 11 — Define payload-opaque network protocol and fake provider

- **Goal:** document routing、subscription、ack/resync、backpressure を EGW payload から分離。
- **Motivation:** Canopy collaboration ADR の5層分離を再利用。
- **Scope:** envelope/control reducer、bounded queues、presence namespace separate。
- **Out of scope:** WebSocket implementation。
- **Proposed API:** `CollabState + Event -> (State, Decision[])`, `Subscribe`, `Data`, `Ack`, `ResyncRequired`。
- **Acceptance:** stale envelopes reject、overflow→resync、payload opaque。session-bound document と envelope DocumentId の不一致を reject。
- **Tests:** slow peer/watchdog/reconnect state-machine properties。
- **Dependencies:** #7,#10。
- **Risks:** EGW peer_sync と generic runtime の責務重複。

### Issue 12 — Implement WebSocket relay and server persistence

- **Goal:**別端末 sync を常時利用可能にする。
- **Motivation:** peer absenceでも後続参加者へ状態を渡すには server durability が必要。
- **Scope:** auth guest session、server-bound doc subscription、cross-document replay rejection、persisted checkpoint/journal、fan-out、metrics。
- **Out of scope:** canonical promotion。
- **Proposed API:** `/documents/:id/sync`, websocket control/data envelopes。
- **Acceptance:** reconnect after server/client restart、slow peer bounded、5k delta/full sync。
- **Tests:** two-browser、fault injection、relay restart。
- **Dependencies:** #11,#9。
- **Risks:** multi-instance writer coordination、DB cost。MoonBit policy + TS/Worker shellを許容。

### Issue 13 — Ship one-city constrained-content MVP

- **Goal:**一人/二人の core loop を常時公開。
- **Motivation:** CRDT demo ではなくゲーム価値を検証。
- **Scope:** Home/Incidents/Detail/Composer/My Contributions/Sync、3 seed incidents、templates、manual steward。
- **Out of scope:** voting、AI、free-form auto-public。
- **Proposed API:** view models と TEA `Msg`, `Cmd`; no new EGW API。
- **Acceptance:** first post <5min、offline submit/reconnect、later-use link。
- **Tests:** usability script、DOM/e2e、empty/error/offline states。
- **Dependencies:** #12,#6。
- **Risks:** moderation capacity、seed quality。ゲーム面白さは別途 human playtest。

### Issue 14 — Add multi-document catalog, archive, and Echo routing

- **Goal:**5–10 incidents、archive、past→new seed、partial subscriptions。
- **Motivation:**常設世界と mega-document 回避。
- **Scope:** WorldCatalogProjection、Region/Incident/Canon docs、archive/late routing。
- **Out of scope:** cross-region simulation。
- **Proposed API:** `DocumentRoute`, `ArchiveDecision`, `LateContributionRoute`。
- **Acceptance:** archive後 raw late writeなし、Echoに保存、subscription memory bound。
- **Tests:** many docs、switch、cold restore、archive race。
- **Dependencies:** #13。
- **Risks:** broken cross-doc refs、projection lag。

### Issue 15 — Add authoritative promotion, roles, moderation, and rate limits

- **Goal:** ConfirmedEvent/Resolution を安全に作る。
- **Motivation:** CRDT convergence では canonicality/one-vote/security を決められない。
- **Scope:** command gateway、request dedup、role grants、decision ledger、manual promotion、visibility filter。
- **Out of scope:** AI auto-promotion。
- **Proposed API:** `decide_promotion(snapshot, policy, request) -> Decision`, `authorize(role, command)`。
- **Acceptance:** untrusted raw sync never mutates canonical doc、decision source/rule/audit complete。
- **Tests:** authz matrix、spam/race/duplicate/stale/appeal。
- **Dependencies:** #14,#12。
- **Risks:** single-writer availability、moderator abuse、PII retention。

### Issue 16 — Add projection/index/history/observability service

- **Goal:** search、catalog、causal/use graph、metrics/tracing を rebuildable にする。
- **Motivation:** client が world 全体を load しないため。
- **Scope:** versioned projections、rebuild command、redacted traces。
- **Out of scope:** AI。
- **Proposed API:** `ProjectionInput -> ProjectionDelta`, query endpoints。
- **Acceptance:** deterministic rebuild hash、lag metrics、no body/PII logs。
- **Tests:** replay/rebuild、large history、index corruption recovery。
- **Dependencies:** #14,#15。
- **Risks:** eventual consistency UX、projection version drift。

### Issue 17 — Add AI assistance as reviewable artifacts

- **Goal:** summary、unresolved points、classification/scene/seed candidates。
- **Motivation:**low activity/onboarding を支援し、人間の判断を置換しない。
- **Scope:** prompt input snapshot、provenance、proposal storage、approval UI。
- **Out of scope:** AI canonical mutation、secret moderation context leakage。
- **Proposed API:** `AiProposal { sources, input_versions, model, prompt_version, body }`。
- **Acceptance:** every output proposal/derived、approval without source drift、disableしても game成立。
- **Tests:** prompt injection、stale source、hallucinated refs、PII redaction。
- **Dependencies:** #15,#16。
- **Risks:** cost、bias、copyright、moderation amplification。

### Issue 18 — Run staged load, fault, retention, and disaster-recovery gates

- **Goal:** 10/100/500接続と1M distributed operations の運用限界を測る。
- **Motivation:** core benchmark と end-to-end SLO を分離し公開判断する。
- **Scope:** JS/wasm core bench、relay fan-out、restore/reconnect、chaos、backup/restore、rematerialization。
- **Out of scope:** measured evidenceなしの optimization。
- **Proposed API:** benchmark fixtures/metrics only。
- **Acceptance:** candidate SLO の採否、document operation budget、runbook、rollback gate。
- **Tests:** destructive suite 全件、regional outage/DB rollback/slow peer。
- **Dependencies:** #16（AIは不要）。
- **Risks:** benchmark representativeness、cost、false confidence。

---

## 結論

技術判断は **GO WITH GATES**。

Event Graph Walker v0.6.0 は、tree、atomic properties、block text、operation sync、causal history、peer-sync decision core を既に提供し、Living Chronicle の collaborative substrate として適している。ただし production local-first runtime、durability、security、multi-document routing、true compaction は提供しない。

最重要の設計は次の3点である。

1. **大人数が完成文章を直接編集せず、immutable contribution を追加する。**
2. **untrusted command と canonical world state の間に authoritative gateway を置く。**
3. **typed-spreadsheet と同じく、local/remote の両方を merged EGW authority から一つの pure projection path へ流す。**

ゲーム面の最大リスクは「技術的に収束するが、読む価値のない断片が増えること」。技術面の最大リスクは「CRDT sync を authorization と誤認し、raw client operations を canonical document に適用すること」。前者は hook設計・curation・content lifecycle、後者は command gateway・document ACL・server-owned canon で別々に解く。
