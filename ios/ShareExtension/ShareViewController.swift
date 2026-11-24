// Share Extension: hands what the user shared (photos, files, links, text)
// to HobCrew, which then asks which Hob gets it.
//
// Writes the same hand-over the receive_sharing_intent plugin reads in the
// app (Apache-2.0, https://github.com/KasemJaffer/receive_sharing_intent):
// a JSON list of {path, mimeType, type} under "ShareKey" in the app group's
// UserDefaults, files copied into the app group container, then opens
// "ShareMedia-<host bundle id>:share". It is self-contained on purpose: the
// plugin's own controller would pull the Flutter engine into the extension.

import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

private struct SharedMediaFile: Codable {
  var path: String
  var mimeType: String?
  var thumbnail: String?
  var duration: Double?
  var message: String?
  var type: String  // image, video, text, file, url
}

class ShareViewController: UIViewController {
  private var hostBundleId = ""
  private var appGroupId = ""

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    if let dot = bundleId.lastIndex(of: ".") {
      hostBundleId = String(bundleId[..<dot])
    }
    appGroupId =
      (Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String)
      ?? "group.\(hostBundleId)"
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    collect { [weak self] files in
      guard let self = self else { return }
      if files.isEmpty {
        self.extensionContext?.cancelRequest(
          withError: NSError(domain: "HobsShare", code: 1))
        return
      }
      self.save(files)
      self.openHostApp()
    }
  }

  // MARK: - Collecting

  private func collect(_ done: @escaping ([SharedMediaFile]) -> Void) {
    let providers =
      (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    var results = [SharedMediaFile?](repeating: nil, count: providers.count)
    let group = DispatchGroup()
    for (i, provider) in providers.enumerated() {
      group.enter()
      load(provider) { file in
        results[i] = file
        group.leave()
      }
    }
    group.notify(queue: .main) { done(results.compactMap { $0 }) }
  }

  private func load(
    _ provider: NSItemProvider, _ done: @escaping (SharedMediaFile?) -> Void
  ) {
    let image = UTType.image.identifier
    let fileURL = UTType.fileURL.identifier
    let url = UTType.url.identifier
    let text = UTType.plainText.identifier

    if provider.hasItemConformingToTypeIdentifier(image) {
      provider.loadItem(forTypeIdentifier: image) { [weak self] data, _ in
        done(self?.storeImage(data))
      }
    } else if provider.hasItemConformingToTypeIdentifier(fileURL)
      || provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        && !provider.hasItemConformingToTypeIdentifier(url)
        && !provider.hasItemConformingToTypeIdentifier(text)
    {
      let type =
        provider.hasItemConformingToTypeIdentifier(fileURL)
        ? fileURL : UTType.data.identifier
      provider.loadItem(forTypeIdentifier: type) { [weak self] data, _ in
        guard let self = self else { return done(nil) }
        if let u = data as? URL, u.isFileURL {
          done(self.storeFile(u, type: "file"))
        } else if let d = data as? Data {
          done(self.storeData(d, name: provider.suggestedName ?? "file", type: "file"))
        } else {
          done(nil)
        }
      }
    } else if provider.hasItemConformingToTypeIdentifier(url) {
      provider.loadItem(forTypeIdentifier: url) { [weak self] data, _ in
        guard let u = data as? URL else { return done(nil) }
        if u.isFileURL {
          done(self?.storeFile(u, type: "file"))
        } else {
          done(SharedMediaFile(path: u.absoluteString, mimeType: nil, type: "url"))
        }
      }
    } else if provider.hasItemConformingToTypeIdentifier(text) {
      provider.loadItem(forTypeIdentifier: text) { data, _ in
        if let s = data as? String {
          done(SharedMediaFile(path: s, mimeType: "text/plain", type: "text"))
        } else if let d = data as? Data, let s = String(data: d, encoding: .utf8) {
          done(SharedMediaFile(path: s, mimeType: "text/plain", type: "text"))
        } else {
          done(nil)
        }
      }
    } else {
      done(nil)
    }
  }

  private func storeImage(_ data: NSSecureCoding?) -> SharedMediaFile? {
    if let u = data as? URL, u.isFileURL { return storeFile(u, type: "image") }
    if let d = data as? Data { return storeData(d, name: "photo.jpg", type: "image") }
    if let img = data as? UIImage, let png = img.pngData() {
      return storeData(png, name: "photo.png", type: "image")
    }
    return nil
  }

  /// A fresh folder in the app group container per item, so equal names
  /// never overwrite each other.
  private func newFolder() -> URL? {
    guard
      let base = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else { return nil }
    let dir = base.appendingPathComponent("Shared", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func storeFile(_ src: URL, type: String) -> SharedMediaFile? {
    guard let dir = newFolder() else { return nil }
    let name = src.lastPathComponent.isEmpty ? "file" : src.lastPathComponent
    let dst = dir.appendingPathComponent(name)
    let scoped = src.startAccessingSecurityScopedResource()
    defer { if scoped { src.stopAccessingSecurityScopedResource() } }
    do {
      try FileManager.default.copyItem(at: src, to: dst)
    } catch {
      return nil
    }
    return SharedMediaFile(path: "file://" + dst.path, mimeType: mime(dst), type: type)
  }

  private func storeData(_ data: Data, name: String, type: String) -> SharedMediaFile? {
    guard let dir = newFolder() else { return nil }
    let dst = dir.appendingPathComponent(name)
    do {
      try data.write(to: dst)
    } catch {
      return nil
    }
    return SharedMediaFile(path: "file://" + dst.path, mimeType: mime(dst), type: type)
  }

  private func mime(_ url: URL) -> String? {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
  }

  // MARK: - Handing over

  private func save(_ files: [SharedMediaFile]) {
    let defaults = UserDefaults(suiteName: appGroupId)
    if let data = try? JSONEncoder().encode(files) {
      defaults?.set(data, forKey: "ShareKey")
    }
    defaults?.removeObject(forKey: "ShareMessageKey")
    defaults?.synchronize()
  }

  private func openHostApp() {
    guard let url = URL(string: "ShareMedia-\(hostBundleId):share") else { return }
    // Extensions cannot reach UIApplication.shared; the responder chain
    // leads to it (iOS 18+), older systems answer the openURL: selector.
    var responder: UIResponder? = self
    let legacyOpen = sel_registerName("openURL:")
    while let r = responder {
      if let app = r as? UIApplication {
        app.open(url, options: [:], completionHandler: nil)
        break
      }
      if #unavailable(iOS 18.0), r.responds(to: legacyOpen) {
        _ = r.perform(legacyOpen, with: url)
        break
      }
      responder = r.next
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
