import Foundation

// Vector artwork for Icon Composer. The system supplies the outer macOS mask,
// glass lighting and shadows; do not bake them into these transparent layers.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Mandroid/AppIcon.icon")
let assets = destination.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func svg(_ name: String, _ body: String) throws {
    let text = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    \(body)
    </svg>
    """
    try text.write(to: assets.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}

try svg("Window", """
<rect x="152" y="184" width="720" height="656" rx="88" fill="#152b3d"/>
""")
try svg("Titlebar", """
<path d="M240 184H784A88 88 0 0 1 872 272V316H152V272A88 88 0 0 1 240 184Z" fill="#e5f0f5"/>
<g fill="#314b5c">
<circle cx="224" cy="252" r="17"/>
<circle cx="282" cy="252" r="17"/>
<circle cx="340" cy="252" r="17"/>
</g>
""")
// A single silhouette with real eye cutouts stays legible in clear/tinted modes.
try svg("Android", """
<path fill="#3de58d" fill-rule="evenodd" d="M276 648C276 555 324 476 395 435L354 377Q346 364 358 356Q370 348 379 361L422 423Q512 384 602 423L645 361Q654 348 666 356Q678 364 670 377L629 435C700 476 748 555 748 648V683Q748 708 723 708H301Q276 708 276 683Z M422 552A25 25 0 1 0 422 602A25 25 0 1 0 422 552Z M602 552A25 25 0 1 0 602 602A25 25 0 1 0 602 552Z"/>
""")

let manifest = """
{
  "color-space-for-untagged-svg-colors": "display-p3",
  "fill": {"linear-gradient": ["srgb:0.20,0.39,0.47,1", "srgb:0.055,0.13,0.21,1"]},
  "groups": [
    {
      "name": "Glass window", "lighting": "individual",
      "layers": [{"name": "Window", "image-name": "Window.svg", "glass": true}],
      "shadow": {"kind": "neutral", "opacity": 0.25},
      "translucency": {"enabled": false, "value": 0.32}
    },
    {
      "name": "Mac titlebar", "lighting": "individual",
      "layers": [{"name": "Titlebar", "image-name": "Titlebar.svg", "glass": true}],
      "shadow": {"kind": "neutral", "opacity": 0.12},
      "translucency": {"enabled": true, "value": 0.22}
    },
    {
      "name": "Android", "lighting": "individual",
      "layers": [{"name": "Android", "image-name": "Android.svg", "glass": true}],
      "shadow": {"kind": "layer-color", "opacity": 0.32},
      "translucency": {"enabled": false, "value": 0.5}
    }
  ],
  "supported-platforms": {"circles": [], "squares": "shared"}
}
"""
// Icon Composer stores frontmost groups first.
var document = try JSONSerialization.jsonObject(with: Data(manifest.utf8)) as! [String: Any]
document["groups"] = (document["groups"] as! [[String: Any]]).reversed().map { $0 }
let encoded = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
try String(decoding: encoded, as: UTF8.self).write(to: destination.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
