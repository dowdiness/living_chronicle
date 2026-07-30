///|
priv struct RestoreFixture {
  encoded : String
  checkpoint_bytes : Int
  incident : @container.TreeNodeId
  contribution_count : Int
  text_codepoints : Int
  expected_tree_operations : Int
  expected_text_operations : Int
  first_contribution : @container.TreeNodeId?
  last_contribution : @container.TreeNodeId?
}

///|
fn restore_fixture(
  label : String,
  contribution_count : Int,
  text_codepoints : Int,
) -> RestoreFixture {
  let source = try! @container.Document::new("phase0-\{label}-source")
  let incident = try! source.create_node(parent=@container.root_id)
  let mut first_contribution : @container.TreeNodeId? = None
  let mut last_contribution : @container.TreeNodeId? = None
  for index in 0..<contribution_count {
    let contribution = try! source.create_node(parent=incident)
    source.set_property(contribution, "body", "fragment-\{index}")
    if first_contribution is None {
      first_contribution = Some(contribution)
    }
    last_contribution = Some(contribution)
  }
  for index in 0..<text_codepoints {
    try! source.insert_text(incident, index, "x")
  }
  let encoded = (try! source.sync().export_all()).to_json_string()
  {
    encoded,
    checkpoint_bytes: @utf8.encode(encoded).length(),
    incident,
    contribution_count,
    text_codepoints,
    expected_tree_operations: 1 + contribution_count * 2,
    expected_text_operations: text_codepoints,
    first_contribution,
    last_contribution,
  }
}

///|
fn verify_restore_fixture(
  fixture : RestoreFixture,
  label : String,
) -> Unit raise {
  let receiver = try! @container.Document::new("phase0-\{label}-verify")
  let message = try! receiver.sync().decode_json(fixture.encoded)
  let report = try! receiver.sync().apply(message)
  assert_eq(report.applied_tree_operations(), fixture.expected_tree_operations)
  assert_eq(report.applied_text_operations(), fixture.expected_text_operations)
  assert_eq(receiver.sync().pending_sync_count(), 0)
  assert_eq(
    receiver.children(fixture.incident).length(),
    fixture.contribution_count,
  )
  assert_eq(receiver.text_len(fixture.incident), fixture.text_codepoints)
  if fixture.text_codepoints > 0 {
    assert_eq(
      receiver.get_text(fixture.incident),
      "x".repeat(fixture.text_codepoints),
    )
  }
  match (fixture.first_contribution, fixture.last_contribution) {
    (Some(first), Some(last)) => {
      assert_eq(receiver.get_property(first, "body"), Some("fragment-0"))
      assert_eq(
        receiver.get_property(last, "body"),
        Some("fragment-\{fixture.contribution_count - 1}"),
      )
    }
    (None, None) => assert_eq(fixture.contribution_count, 0)
    _ => fail("fixture contribution endpoints must agree")
  }
}

///|
fn print_fixture_metadata(label : String, fixture : RestoreFixture) -> Unit {
  println(
    "\{label}: checkpoint_bytes=\{fixture.checkpoint_bytes} " +
    "tree_ops=\{fixture.expected_tree_operations} " +
    "text_ops=\{fixture.expected_text_operations}",
  )
}

///|
fn bench_restore(
  b : @bench.T,
  label : String,
  fixture : RestoreFixture,
) -> Unit raise {
  verify_restore_fixture(fixture, label)
  print_fixture_metadata(label, fixture)
  b.bench(fn() {
    let receiver = try! @container.Document::new("phase0-\{label}-receiver")
    let message = try! receiver.sync().decode_json(fixture.encoded)
    let report = try! receiver.sync().apply(message)
    b.keep(
      (
        fixture.checkpoint_bytes,
        report.applied_tree_operations(),
        report.applied_text_operations(),
      ),
    )
  })
}

///|
test "phase0 restore 1k atomic-property contributions" (b : @bench.T) {
  bench_restore(b, "property-1k", restore_fixture("property-1k", 1_000, 0))
}

///|
test "phase0 restore 1k block-text codepoints" (b : @bench.T) {
  bench_restore(b, "text-1k", restore_fixture("text-1k", 0, 1_000))
}

///|
/// 1,000 total operations: one incident create, 250 contribution creates,
/// 250 body properties, and 499 block-text insert operations.
test "phase0 restore mixed 1k operations" (b : @bench.T) {
  let fixture = restore_fixture("mixed-1k", 250, 499)
  assert_eq(
    fixture.expected_tree_operations + fixture.expected_text_operations,
    1_000,
  )
  bench_restore(b, "mixed-1k", fixture)
}

///|
/// 10,000 total operations: one incident create, 2,500 contribution creates,
/// 2,500 body properties, and 4,999 block-text insert operations.
test "phase0 restore mixed 10k operations" (b : @bench.T) {
  let fixture = restore_fixture("mixed-10k", 2_500, 4_999)
  assert_eq(
    fixture.expected_tree_operations + fixture.expected_text_operations,
    10_000,
  )
  assert_true(fixture.checkpoint_bytes <= 8 * 1024 * 1024)
  bench_restore(b, "mixed-10k", fixture)
}
