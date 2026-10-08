///|
fn scene_fixture(source : String) -> Json {
  @json.parse(source) catch {
    _ => abort("valid scene fixture")
  }
}

///|
fn valid_scene() -> Json {
  scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":320,\"height\":240},\"scale\":1,\"resources\":[],\"clip_chains\":[{\"id\":0,\"rects\":[{\"x\":0,\"y\":0,\"width\":320,\"height\":240}]}],\"items\":[{\"id\":18446744073709550000,\"kind\":\"text\",\"bounds\":{\"x\":8,\"y\":12,\"width\":200,\"height\":32},\"color\":{\"red\":10,\"green\":20,\"blue\":30,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":0,\"text\":\"日本語😀\",\"font_size\":15}]}",
  )
}

///|
test "canvas accepts bounded SceneSnapshot v1 scenes and large integer IDs" {
  assert_true(
    @browser.validate_scene(valid_scene(), 320.0, 240.0, 2.0) is Ok(_),
  )
  assert_true(@browser.validate_scene(valid_scene(), 0.0, 240.0, 1.0) is Err(_))
}

///|
test "canvas rejects unsupported resources before painting" {
  let snapshot = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[{}],\"clip_chains\":[],\"items\":[]}",
  )
  match @browser.validate_scene(snapshot, 1.0, 1.0, 1.0) {
    Err(error) => {
      assert_eq(error.code(), "unsupported_capability")
      assert_true(error.message().contains("resource-backed"))
    }
    Ok(_) => fail("resource-backed scenes are outside the Canvas v1 subset")
  }
}

///|
test "canvas rejects malformed unused clip chains and dangling clip references" {
  let malformed_unused_chain = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[{\"id\":1,\"rects\":[{\"x\":0,\"y\":0,\"width\":-1,\"height\":1}]}],\"items\":[]}",
  )
  assert_true(
    @browser.validate_scene(malformed_unused_chain, 1.0, 1.0, 1.0) is Err(_),
  )
  let dangling_reference = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"id\":1,\"kind\":\"quad\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"color\":{\"red\":0,\"green\":0,\"blue\":0,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":4}]}",
  )
  match @browser.validate_scene(dangling_reference, 1.0, 1.0, 1.0) {
    Err(error) => assert_true(error.message().contains("unknown clip chain"))
    Ok(_) => fail("the complete scene should be rejected before painting")
  }
}

///|
test "canvas validates text limits, color channels, and transform finiteness" {
  let invalid_color = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"id\":1,\"kind\":\"quad\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"color\":{\"red\":256,\"green\":0,\"blue\":0,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null}]}",
  )
  assert_true(@browser.validate_scene(invalid_color, 1.0, 1.0, 1.0) is Err(_))
  let invalid_transform = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[{\"id\":1,\"kind\":\"quad\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"color\":{\"red\":0,\"green\":0,\"blue\":0,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":\"bad\"},\"opacity\":1,\"clip_chain_id\":null}]}",
  )
  assert_true(
    @browser.validate_scene(invalid_transform, 1.0, 1.0, 1.0) is Err(_),
  )
  let overlong_text = "x".repeat(65537)
  let snapshot = scene_fixture(
    "{\"schema_version\":1,\"viewport\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"scale\":1,\"resources\":[],\"clip_chains\":[],\"items\":[]}",
  )
  match snapshot {
    Json::Object(fields) => {
      let item = scene_fixture(
        "{\"id\":1,\"kind\":\"text\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"color\":{\"red\":0,\"green\":0,\"blue\":0,\"alpha\":255},\"transform\":{\"a\":1,\"b\":0,\"c\":0,\"d\":1,\"tx\":0,\"ty\":0},\"opacity\":1,\"clip_chain_id\":null,\"text\":\"\",\"font_size\":12}",
      )
      match item {
        Json::Object(item_fields) =>
          item_fields["text"] = Json::string(overlong_text)
        _ => fail("text item fixture should be an object")
      }
      fields["items"] = Json::array([item])
      assert_true(
        @browser.validate_scene(Json::object(fields), 1.0, 1.0, 1.0) is Err(_),
      )
    }
    _ => fail("scene fixture should be an object")
  }
}
