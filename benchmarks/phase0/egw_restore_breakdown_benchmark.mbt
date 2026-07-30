///|
priv struct PropertyReplayFixture {
  encoded : String
  checkpoint_bytes : Int
  incident : @container.TreeNodeId
  contributions : Array[@container.TreeNodeId]
  expected_operations : Int
  interleaved : Bool
}

///|
/// Build equal-shape property fixtures whose only intentional difference is
/// causal operation order. Grouped fixtures create every child before setting
/// any properties. Interleaved fixtures set each child's property immediately
/// after creating it.
fn property_replay_fixture(
  label : String,
  total_operations : Int,
  interleaved : Bool,
) -> PropertyReplayFixture {
  guard total_operations >= 2 && total_operations % 2 == 0 else {
    abort("property replay fixture requires a positive even operation count")
  }
  let contribution_count = (total_operations - 2) / 2
  let source = try! @container.Document::new("phase0-\{label}-source")
  let incident = try! source.create_node(parent=@container.root_id)
  let contributions : Array[@container.TreeNodeId] = []
  if interleaved {
    for index in 0..<contribution_count {
      let contribution = try! source.create_node(parent=incident)
      contributions.push(contribution)
      source.set_property(contribution, "body", "fragment-\{index}")
    }
  } else {
    for _index in 0..<contribution_count {
      contributions.push(try! source.create_node(parent=incident))
    }
    for index in 0..<contribution_count {
      source.set_property(contributions[index], "body", "fragment-\{index}")
    }
  }
  source.set_property(incident, "phase", "complete")
  let encoded = (try! source.sync().export_all()).to_json_string()
  {
    encoded,
    checkpoint_bytes: @utf8.encode(encoded).length(),
    incident,
    contributions,
    expected_operations: total_operations,
    interleaved,
  }
}

///|
fn verify_property_replay_fixture(
  fixture : PropertyReplayFixture,
  label : String,
) -> Unit raise {
  let receiver = try! @container.Document::new("phase0-\{label}-verify")
  let message = try! receiver.sync().decode_json(fixture.encoded)
  assert_eq(message.op_count(), fixture.expected_operations)
  let report = try! receiver.sync().apply(message)
  assert_eq(report.applied_tree_operations(), fixture.expected_operations)
  assert_eq(report.applied_text_operations(), 0)
  assert_eq(report.pending_operations(), 0)
  assert_eq(receiver.sync().pending_sync_count(), 0)
  assert_eq(
    receiver.children(fixture.incident).length(),
    fixture.contributions.length(),
  )
  assert_eq(receiver.get_property(fixture.incident, "phase"), Some("complete"))
  if !fixture.contributions.is_empty() {
    assert_eq(
      receiver.get_property(fixture.contributions[0], "body"),
      Some("fragment-0"),
    )
    let last_index = fixture.contributions.length() - 1
    assert_eq(
      receiver.get_property(fixture.contributions[last_index], "body"),
      Some("fragment-\{last_index}"),
    )
  }
}

///|
fn print_property_fixture_metadata(
  label : String,
  fixture : PropertyReplayFixture,
) -> Unit {
  println(
    "\{label}: checkpoint_bytes=\{fixture.checkpoint_bytes} " +
    "tree_ops=\{fixture.expected_operations} " +
    "contributions=\{fixture.contributions.length()} " +
    "interleaved=\{fixture.interleaved}",
  )
}

///|
fn bench_receiver_decode(
  b : @bench.T,
  label : String,
  fixture : PropertyReplayFixture,
) -> Unit raise {
  verify_property_replay_fixture(fixture, label)
  print_property_fixture_metadata(label, fixture)
  let receiver = try! @container.Document::new("phase0-\{label}-decoder")
  b.bench(fn() {
    let message = try! receiver.sync().decode_json(fixture.encoded)
    b.keep((message.op_count(), fixture.checkpoint_bytes))
  })
}

///|
fn bench_predecoded_apply(
  b : @bench.T,
  label : String,
  fixture : PropertyReplayFixture,
) -> Unit raise {
  verify_property_replay_fixture(fixture, label)
  print_property_fixture_metadata(label, fixture)
  let decoder = try! @container.Document::new("phase0-\{label}-decoder")
  let message = try! decoder.sync().decode_json(fixture.encoded)
  b.bench(fn() {
    let receiver = try! @container.Document::new("phase0-\{label}-receiver")
    let report = try! receiver.sync().apply(message)
    b.keep(
      (
        report.applied_tree_operations(),
        report.applied_text_operations(),
        report.pending_operations(),
      ),
    )
  })
}

///|
test "phase0 property replay fixture order preserves final projection" {
  let grouped = property_replay_fixture("grouped-check", 100, false)
  let interleaved = property_replay_fixture("interleaved-check", 100, true)
  verify_property_replay_fixture(grouped, "grouped-check")
  verify_property_replay_fixture(interleaved, "interleaved-check")
}

///|
test "phase0 restore receiver construction baseline" (b : @bench.T) {
  b.bench(fn() {
    let receiver = try! @container.Document::new("phase0-receiver-baseline")
    b.keep(receiver.version())
  })
}

///|
test "phase0 restore decode grouped 1k operations" (b : @bench.T) {
  bench_receiver_decode(
    b,
    "decode-grouped-1k",
    property_replay_fixture("decode-grouped-1k", 1_000, false),
  )
}

///|
test "phase0 restore decode grouped 5k operations" (b : @bench.T) {
  bench_receiver_decode(
    b,
    "decode-grouped-5k",
    property_replay_fixture("decode-grouped-5k", 5_000, false),
  )
}

///|
test "phase0 restore decode grouped 10k operations" (b : @bench.T) {
  let fixture = property_replay_fixture("decode-grouped-10k", 10_000, false)
  assert_true(fixture.checkpoint_bytes <= 8 * 1024 * 1024)
  bench_receiver_decode(b, "decode-grouped-10k", fixture)
}

///|
test "phase0 restore apply grouped 1k operations" (b : @bench.T) {
  bench_predecoded_apply(
    b,
    "apply-grouped-1k",
    property_replay_fixture("apply-grouped-1k", 1_000, false),
  )
}

///|
test "phase0 restore apply grouped 5k operations" (b : @bench.T) {
  bench_predecoded_apply(
    b,
    "apply-grouped-5k",
    property_replay_fixture("apply-grouped-5k", 5_000, false),
  )
}

///|
test "phase0 restore apply grouped 10k operations" (b : @bench.T) {
  let fixture = property_replay_fixture("apply-grouped-10k", 10_000, false)
  assert_true(fixture.checkpoint_bytes <= 8 * 1024 * 1024)
  bench_predecoded_apply(b, "apply-grouped-10k", fixture)
}

///|
test "phase0 restore apply interleaved 1k operations" (b : @bench.T) {
  bench_predecoded_apply(
    b,
    "apply-interleaved-1k",
    property_replay_fixture("apply-interleaved-1k", 1_000, true),
  )
}

///|
test "phase0 restore apply interleaved 5k operations" (b : @bench.T) {
  bench_predecoded_apply(
    b,
    "apply-interleaved-5k",
    property_replay_fixture("apply-interleaved-5k", 5_000, true),
  )
}

///|
test "phase0 restore apply interleaved 10k operations" (b : @bench.T) {
  let fixture = property_replay_fixture("apply-interleaved-10k", 10_000, true)
  assert_true(fixture.checkpoint_bytes <= 8 * 1024 * 1024)
  bench_predecoded_apply(b, "apply-interleaved-10k", fixture)
}
