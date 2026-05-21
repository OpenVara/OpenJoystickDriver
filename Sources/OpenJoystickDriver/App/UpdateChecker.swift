import Foundation
import OpenJoystickDriverKit

struct UpdateInfo: Equatable, Sendable {
  let tagName: String
  let version: SemanticVersion
  let htmlURL: URL
}

enum UpdateCheckState: Equatable, Sendable {
  case idle
  case checking
  case upToDate(String)
  case available(UpdateInfo)
  case failed(String)
}

struct UpdateChecker {
  private static var defaultLatestReleaseURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.github.com"
    components.path = "/repos/xsyetopz/OpenJoystickDriver/releases/latest"
    return components.url ?? URL(fileURLWithPath: "/")
  }

  private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
      case draft
    }
  }

  let latestReleaseURL: URL
  let session: URLSession

  init(
    latestReleaseURL: URL = Self.defaultLatestReleaseURL,
    session: URLSession = .shared
  ) {
    self.latestReleaseURL = latestReleaseURL
    self.session = session
  }

  func check(currentVersion rawCurrentVersion: String) async -> UpdateCheckState {
    guard let currentVersion = SemanticVersion(rawCurrentVersion) else {
      return .failed("Current app version is not SemVer: \(rawCurrentVersion)")
    }

    do {
      var request = URLRequest(url: latestReleaseURL)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("OpenJoystickDriver", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await data(for: request)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        return .failed("GitHub returned HTTP \(http.statusCode)")
      }

      let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
      guard !release.draft else { return .failed("Latest GitHub release is a draft") }
      guard let latestVersion = SemanticVersion(release.tagName) else {
        return .failed("Latest GitHub release tag is not SemVer: \(release.tagName)")
      }

      let info = UpdateInfo(
        tagName: release.tagName,
        version: latestVersion,
        htmlURL: release.htmlURL
      )
      return latestVersion > currentVersion ? .available(info) : .upToDate(rawCurrentVersion)
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let task = session.dataTask(with: request) { data, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let data, let response else {
          continuation.resume(throwing: URLError(.badServerResponse))
          return
        }
        continuation.resume(returning: (data, response))
      }
      task.resume()
    }
  }
}
