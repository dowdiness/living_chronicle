///|
/// Replaying an exact full-sync message is idempotent and reports duplicates
/// instead of applying the operations twice.
test "phase0 duplicate full sync is idempotent" {
  let source = try! @container.Document::new("phase0-duplicate-source")
  let incident = try! source.create_node(parent=@container.root_id)
  source.set_property(incident, "state", "open")
  try! source.insert_text(incident, 0, "seed")
  let message = try! source.sync().export_all()

  let peer = try! @container.Document::new("phase0-duplicate-peer")
  let first = try! peer.sync().apply(message)
  let second = try! peer.sync().apply(message)

  assert_eq(first.pending_operations(), 0)
  assert_eq(second.pending_operations(), 0)
  assert_eq(second.duplicate_operations(), message.op_count())
  assert_eq(second.applied_tree_operations(), 0)
  assert_eq(second.applied_text_operations(), 0)
  assert_eq(peer.get_text(incident), "seed")
  assert_eq(peer.get_property(incident, "state"), Some("open"))
}

///|
/// Concurrent contribution appends converge even when receivers apply the two
/// deltas in opposite orders.
test "phase0 concurrent appends converge across delivery permutations" {
  let host = try! @container.Document::new("phase0-host")
  let incident = try! host.create_node(parent=@container.root_id)
  host.set_property(incident, "kind", "incident")
  let bootstrap = try! host.sync().export_all()
  let bootstrap_version = host.version()

  let alice = try! @container.Document::new("phase0-alice")
  let bob = try! @container.Document::new("phase0-bob")
  ignore(try! alice.sync().apply(bootstrap))
  ignore(try! bob.sync().apply(bootstrap))

  let alice_contribution = try! alice.create_node(parent=incident)
  alice.set_property(alice_contribution, "kind", "observation")
  alice.set_property(alice_contribution, "body", "bells under the river")
  let alice_delta = try! alice.sync().export_since(bootstrap_version)

  let bob_contribution = try! bob.create_node(parent=incident)
  bob.set_property(bob_contribution, "kind", "action")
  bob.set_property(bob_contribution, "body", "follow the lantern keeper")
  let bob_delta = try! bob.sync().export_since(bootstrap_version)

  let alice_then_bob = try! @container.Document::new("phase0-left")
  let bob_then_alice = try! @container.Document::new("phase0-right")
  ignore(try! alice_then_bob.sync().apply(bootstrap))
  ignore(try! bob_then_alice.sync().apply(bootstrap))
  ignore(try! alice_then_bob.sync().apply(alice_delta))
  ignore(try! alice_then_bob.sync().apply(bob_delta))
  ignore(try! bob_then_alice.sync().apply(bob_delta))
  ignore(try! bob_then_alice.sync().apply(alice_delta))

  assert_eq(
    alice_then_bob.children(incident),
    bob_then_alice.children(incident),
  )
  assert_eq(alice_then_bob.version(), bob_then_alice.version())
  assert_eq(
    (try! alice_then_bob.sync().export_all()).to_canonical_bytes(),
    (try! bob_then_alice.sync().export_all()).to_canonical_bytes(),
  )
  assert_eq(
    alice_then_bob.get_property(alice_contribution, "body"),
    Some("bells under the river"),
  )
  assert_eq(
    alice_then_bob.get_property(bob_contribution, "body"),
    Some("follow the lantern keeper"),
  )
}

///|
/// Receiver limits reject an oversized full-sync batch before mutating the
/// receiver, so product-level checkpoint budgets can rely on failure atomicity.
test "phase0 decoded operation limit rejects full sync atomically" {
  let source = try! @container.Document::new("phase0-limit-source")
  ignore(try! source.create_node(parent=@container.root_id))
  ignore(try! source.create_node(parent=@container.root_id))
  let message = try! source.sync().export_all()
  let limits = try! @sync.Limits(max_decoded_operations=1)
  let receiver = try! @container.Document::new_with_sync_limits(
    "phase0-limit-receiver", limits,
  )

  try receiver.sync().apply(message) catch {
    @container.DocumentError::SyncFailed(
      @sync.Failure::LimitExceeded(
        kind=@sync.LimitKind::DecodedOperations,
        limit=1,
        actual=2
      )
    ) => ()
    _ => fail("expected decoded-operation limit classification")
  } noraise {
    _ => fail("oversized full sync must fail")
  }

  assert_eq(receiver.version(), @container.Version::empty())
  assert_eq(receiver.children(@container.root_id).length(), 0)
  assert_eq(receiver.sync().pending_sync_count(), 0)
}

///|
/// The encoded checkpoint byte budget is enforced by the receiving document,
/// independently of the sender's limits.
test "phase0 encoded byte limit rejects checkpoint atomically" {
  let source = try! @container.Document::new("phase0-byte-source")
  ignore(try! source.create_node(parent=@container.root_id))
  let encoded = (try! source.sync().export_all()).to_json_string()
  let limits = try! @sync.Limits(max_encoded_bytes=encoded.length() - 1)
  let receiver = try! @container.Document::new_with_sync_limits(
    "phase0-byte-receiver", limits,
  )
  let decoded = try! receiver.sync().decode_json(encoded)

  try receiver.sync().apply(decoded) catch {
    @container.DocumentError::SyncFailed(
      @sync.Failure::LimitExceeded(
        kind=@sync.LimitKind::EncodedBytes,
        limit=_,
        actual=_
      )
    ) => ()
    _ => fail("expected encoded-byte limit classification")
  } noraise {
    _ => fail("oversized checkpoint must fail")
  }

  assert_eq(receiver.version(), @container.Version::empty())
  assert_eq(receiver.children(@container.root_id).length(), 0)
  assert_eq(receiver.sync().pending_sync_count(), 0)
}
