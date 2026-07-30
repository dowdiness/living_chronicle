///|
fn full_property_checkpoint(count : Int) -> String {
  let source = try! @container.Document::new("phase0-property-source")
  let incident = try! source.create_node(parent=@container.root_id)
  for index in 0..<count {
    let contribution = try! source.create_node(parent=incident)
    source.set_property(contribution, "body", "fragment-\{index}")
  }
  (try! source.sync().export_all()).to_json_string()
}

///|
fn full_text_checkpoint(count : Int) -> String {
  let source = try! @container.Document::new("phase0-text-source")
  let incident = try! source.create_node(parent=@container.root_id)
  for index in 0..<count {
    try! source.insert_text(incident, index, "x")
  }
  (try! source.sync().export_all()).to_json_string()
}

///|
test "phase0 restore 1k atomic-property contributions" (b : @bench.T) {
  let encoded = full_property_checkpoint(1_000)
  b.bench(fn() {
    let receiver = try! @container.Document::new("phase0-property-receiver")
    let message = try! receiver.sync().decode_json(encoded)
    let report = try! receiver.sync().apply(message)
    b.keep((encoded.length(), report.applied_tree_operations()))
  })
}

///|
test "phase0 restore 1k block-text codepoints" (b : @bench.T) {
  let encoded = full_text_checkpoint(1_000)
  b.bench(fn() {
    let receiver = try! @container.Document::new("phase0-text-receiver")
    let message = try! receiver.sync().decode_json(encoded)
    let report = try! receiver.sync().apply(message)
    b.keep((encoded.length(), report.applied_text_operations()))
  })
}
