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

///|
fn unicode_checkpoint_before_restart() -> (String, @container.TreeNodeId) {
  let source = try! @container.Document::new("phase0-unicode-source")
  let incident = try! source.create_node(parent=@container.root_id)
  try! source.insert_text(incident, 0, "鐘😀𠮷")
  ((try! source.sync().export_all()).to_json_string(), incident)
}

///|
/// Non-BMP codepoints survive full JSON restore and the replacement replica's
/// incremental continuation without surrogate splitting.
test "phase0 unicode survives restore and continuation delta" {
  let (encoded, incident) = unicode_checkpoint_before_restart()

  let peer = try! @container.Document::new("phase0-unicode-peer")
  ignore(try! peer.sync().apply(try! peer.sync().decode_json(encoded)))

  let restored = try! @container.Document::new("phase0-unicode-source")
  ignore(try! restored.sync().apply(try! restored.sync().decode_json(encoded)))
  let checkpoint_version = restored.version()
  try! restored.insert_text(
    incident,
    restored.text_len(incident),
    "—続き🌙",
  )
  restored.set_property(incident, "witness", "川辺の観測者🕯️")

  let continuation = try! restored.sync().export_since(checkpoint_version)
  ignore(try! peer.sync().apply(continuation))

  assert_eq(peer.get_text(incident), "鐘😀𠮷—続き🌙")
  assert_eq(
    peer.get_property(incident, "witness"),
    Some("川辺の観測者🕯️"),
  )
  assert_eq(peer.sync().pending_sync_count(), 0)
}
