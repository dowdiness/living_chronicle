///|
fn checkpoint_before_restart() -> (String, @container.TreeNodeId) {
  let source = try! @container.Document::new("phase0-source")
  let incident = try! source.create_node(parent=@container.root_id)
  source.set_property(incident, "kind", "incident")
  try! source.insert_text(incident, 0, "seed")
  ((try! source.sync().export_all()).to_json_string(), incident)
}

///|
/// After the original replica instance is retired, a full JSON sync export can
/// restore a replacement using that replica ID. The replacement can continue
/// issuing operations without reusing an identity, and an existing peer can
/// consume only the post-restart delta.
test "phase0 restore retired replica then continue editing" {
  let (encoded, incident) = checkpoint_before_restart()

  let peer = try! @container.Document::new("phase0-peer")
  let peer_checkpoint = try! peer.sync().decode_json(encoded)
  ignore(try! peer.sync().apply(peer_checkpoint))

  let restored = try! @container.Document::new("phase0-source")
  let decoded = try! restored.sync().decode_json(encoded)
  let restored_report = try! restored.sync().apply(decoded)
  let checkpoint_version = restored.version()

  assert_eq(restored_report.pending_operations(), 0)
  assert_eq(restored.get_text(incident), "seed")
  restored.set_property(incident, "state", "open")
  try! restored.insert_text(incident, restored.text_len(incident), "-continued")
  let contribution = try! restored.create_node(parent=incident)
  restored.set_property(contribution, "body", "a later fragment")

  let continuation = try! restored.sync().export_since(checkpoint_version)
  ignore(try! peer.sync().apply(continuation))

  assert_eq(peer.get_text(incident), "seed-continued")
  assert_eq(peer.get_property(incident, "state"), Some("open"))
  assert_eq(peer.get_property(contribution, "body"), Some("a later fragment"))
}
