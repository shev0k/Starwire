//
//  AboutScreen.swift
//  Starwire
//
//  About Starwire: the version, the projects it is built on with their authors (StarwireKit's
//  SettingsCredits, the same list as Android's About page plus the iOS ones), and the open-source
//  licences of the code inside the app.
//

import StarwireKit
import SwiftUI
import UIKit

struct AboutScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    static var versionDetails: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return "Starwire \(version) (\(build)), \(device.model), \(device.systemName) \(device.systemVersion)"
    }

    var body: some View {
        ZStack {
            StarfieldBackground(paused: state.isStreaming)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("ios_about_title"))
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            StarwireLogo(paused: state.isStreaming)
                                .frame(width: 72, height: 72)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                RainbowWordmark(paused: state.isStreaming)
                                Text(Self.versionDetails)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .textSelection(.enabled)
                            }
                        }
                        Text(L("ios_about_text"))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            linkButton(L("title_about_source"), "https://github.com/shev0k/Starwire", id: "about-source")
                            Button(L("title_about_licences")) { state.path.append(.licences) }
                                .buttonStyle(.bordered)
                                .controllerFocusable("about-licences") { state.path.append(.licences) }
                        }
                        Text(L("title_about_credits"))
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(SettingsCredits.sectionKeys, id: \.self) { section in
                            let projects = SettingsCredits.projects(inSection: section)
                            if !projects.isEmpty {
                                Text(L(section))
                                    .font(.headline)
                                    .padding(.top, 6)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(projects) { project in
                                    creditRow(project)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("about") { dismiss() }
    }

    private func linkButton(_ title: String, _ url: String, id: String) -> some View {
        Button(title) { open(url) }
            .buttonStyle(.bordered)
            .controllerFocusable(id) { open(url) }
    }

    private func creditRow(_ project: ProjectCredit) -> some View {
        Button { open(project.url) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.project)
                    .font(.body.weight(.semibold))
                Text(project.author)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                Text(L(project.usedForKey))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frostedCard(cornerRadius: 16, padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("ios_opens_website"))
        .controllerFocusable("credit-\(project.project)", cornerRadius: 16) { open(project.url) }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) {
            UIApplication.shared.open(url)
        }
    }
}

/// The open-source code inside the iOS app and its licences.
struct LicencesScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    struct Notice: Identifiable {
        var id: String { name }
        let name: String
        let licence: String
        let url: String
    }

    static let notices = [
        Notice(name: "Starwire, Moonlight iOS and Moonlight", licence: "GPL-3.0", url: "https://github.com/moonlight-stream/moonlight-ios"),
        Notice(name: "moonlight-common-c (Nonary's fork)", licence: "GPL-3.0", url: "https://github.com/Nonary/moonlight-common-c"),
        Notice(name: "VoidLink", licence: "GPL-3.0", url: "https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm"),
        Notice(name: "ENet", licence: "MIT", url: "https://github.com/lsalzman/enet"),
        Notice(name: "nanors", licence: "MIT", url: "https://github.com/sleepybishop/nanors"),
        Notice(name: "OpenSSL", licence: "Apache-2.0", url: "https://github.com/openssl/openssl"),
        Notice(name: "OpenSSL-Package", licence: "Apache-2.0", url: "https://github.com/krzyzanowskim/OpenSSL-Package"),
        Notice(name: "Opus", licence: "BSD-3-Clause", url: "https://opus-codec.org/license/"),
        Notice(name: "SDL2", licence: "Zlib", url: "https://github.com/libsdl-org/SDL"),
        Notice(name: "FFmpeg", licence: "LGPL-2.1", url: "https://ffmpeg.org/legal.html"),
        Notice(name: "Dear ImGui and ImPlot", licence: "MIT", url: "https://github.com/ocornut/imgui"),
        Notice(name: "TPCircularBuffer", licence: "Zlib", url: "https://github.com/michaeltyson/TPCircularBuffer"),
        Notice(name: "SWRevealViewController", licence: "MIT", url: "https://github.com/John-Lluch/SWRevealViewController"),
        Notice(name: "swift-crypto and swift-asn1", licence: "Apache-2.0", url: "https://github.com/apple/swift-crypto"),
    ]

    var body: some View {
        ZStack {
            StarfieldBackground(paused: state.isStreaming)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("title_about_licences"))
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("ios_licences_text"))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Self.notices) { notice in
                            Button {
                                if let url = URL(string: notice.url) { UIApplication.shared.open(url) }
                            } label: {
                                HStack {
                                    Text(notice.name).font(.body.weight(.semibold))
                                    Spacer()
                                    Text(notice.licence).font(.subheadline.monospaced())
                                }
                                .padding(14)
                                .frostedCard(cornerRadius: 14, padding: 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .controllerFocusable("licence-\(notice.name)", cornerRadius: 14) {
                                if let url = URL(string: notice.url) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("licences") { dismiss() }
    }
}
