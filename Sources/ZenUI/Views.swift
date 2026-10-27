import SwiftUI
import UniformTypeIdentifiers
import ZenCore
#if os(macOS)
import AppKit
#endif

private enum Ink {
    static let paper = Color(red: 0.966, green: 0.958, blue: 0.938)
    static let primary = Color(red: 0.25, green: 0.28, blue: 0.25)
    static let muted = Color(red: 0.44, green: 0.46, blue: 0.42)
    static let accent = Color(red: 0.36, green: 0.43, blue: 0.33)
    static let line = Color(red: 0.83, green: 0.83, blue: 0.77)
}

public struct ZenRootView: View {
    @ObservedObject var model: ZenModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    public init(model: ZenModel) { self.model = model }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("禅").font(.system(size: 24, design: .serif))
                Spacer()
                tab("当下", index: 0)
                tab("留痕", index: 1)
                tab("设置", index: 2)
            }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 18) {
                    if !model.recoveryHealthy {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("本机草稿尚未可靠保存。先处理保存问题，再开始下一轮。")
                            Button("重试保存本机草稿") { model.retryRecovery() }
                        }.font(.callout).padding().background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let message = model.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                            Button("收起提示") { model.errorMessage = nil }.buttonStyle(.borderless)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if model.selectedTab == 0 {
                        if model.directory == nil { WelcomeView(model: model) }
                        else { FocusView(model: model) }
                    } else if model.selectedTab == 1 { RecordsView(model: model) }
                    else { PreferencesView(model: model) }
                }.padding(.horizontal, 28).padding(.vertical, 24)
            }
        }
        .foregroundColor(Ink.primary).background(Ink.paper).tint(Ink.accent).preferredColorScheme(.light)
        .sheet(isPresented: Binding(get: { model.editorID != nil }, set: { if !$0 { model.editorID = nil } })) {
            if let id = model.editorID { AnnotationView(model: model, id: id).id(id) }
        }
        .onAppear {
            #if os(macOS)
            model.openWindow = { openWindow(id: "zen"); NSApp.activate(ignoringOtherApps: true) }
            #endif
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.tick(); model.refresh() }
        }
    }
    private func tab(_ title: String, index: Int) -> some View {
        Button { model.selectedTab = index } label: {
            Text(title).font(.system(size: 12, weight: model.selectedTab == index ? .medium : .regular))
                .foregroundColor(model.selectedTab == index ? Ink.primary : Ink.muted)
                .frame(width: 44, height: 36)
                .overlay(alignment: .bottom) {
                    if index == 1 && model.pendingCount > 0 { Circle().fill(Ink.accent).frame(width: 3, height: 3) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(model.selectedTab == index ? [.isSelected] : [])
            .help(index == 1 && model.pendingCount > 0 ? "有待补记记录" : title)
    }
}

private struct WelcomeView: View {
    @ObservedObject var model: ZenModel
    var body: some View {
        VStack(spacing: 24) {
            Enso(progress: 0).frame(width: 156, height: 156).overlay(Text("禅").font(.system(size: 48, design: .serif)))
                .padding(.top, 30)
            Text("从一段安静的时间开始").font(.system(size: 21, design: .serif))
            Text("选择一个文件夹，安放你的专注记录。\n每次一份 Markdown，随时可读。")
                .font(.callout).foregroundColor(Ink.muted).multilineTextAlignment(.center).lineSpacing(7)
            DirectoryButton(model: model, title: "选择数据文件夹").buttonStyle(ZenButtonStyle())
            Text("无需登录，离线可用。文件同步由你自己安排。")
                .font(.caption).foregroundColor(Ink.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}

// A quiet, tapered stroke. Its shape stays still as the elapsed portion fills in.
private struct EnsoStroke: Shape {
    var progress: Double = 1
    func path(in rect: CGRect) -> Path {
        let end = max(0, min(1, progress))
        guard end > 0 else { return Path() }
        let radius = min(rect.width, rect.height) / 2 - 6
        let steps = max(2, Int(240 * end))
        func point(_ index: Int, side: Double) -> CGPoint {
            let t = Double(index) / Double(steps) * end
            let angle = -Double.pi / 2 + 0.13 + t * (2 * Double.pi - 0.26)
            let organic = 1.4 * sin(3 * angle) + 0.6 * sin(7 * angle)
            let width = 0.35 + 2.1 * pow(sin(Double.pi * t), 0.7)
            let r = radius + organic + side * width / 2
            return CGPoint(x: rect.midX + cos(angle) * r, y: rect.midY + sin(angle) * r)
        }
        var path = Path()
        path.move(to: point(0, side: 1))
        for index in 1...steps { path.addLine(to: point(index, side: 1)) }
        for index in (0...steps).reversed() { path.addLine(to: point(index, side: -1)) }
        path.closeSubpath()
        return path
    }
}

private struct Enso: View {
    var progress: Double
    var body: some View {
        ZStack {
            EnsoStroke().fill(Ink.muted.opacity(0.23))
            EnsoStroke(progress: progress).fill(Ink.accent.opacity(0.6))
        }.accessibilityHidden(true)
    }
}

private struct FocusView: View {
    @ObservedObject var model: ZenModel
    @State private var label = ""
    @State private var choosingSound = false
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Enso(progress: progress)
                Text(durationText(model.active == nil ? model.preferences.focusMinutes * 60 : model.remaining))
                    .font(.system(size: 52, weight: .ultraLight)).monospacedDigit().tracking(2)
                    .accessibilityLabel("剩余时间")
                    .accessibilityValue(durationText(model.active == nil ? model.preferences.focusMinutes * 60 : model.remaining))
            }.frame(width: 242, height: 242).padding(.top, 32)
            if let active = model.active {
                if active.isRest { Text("休息").font(.caption).foregroundColor(Ink.muted) }
                else if !active.label.isEmpty { Text(active.label).font(.callout).foregroundColor(Ink.muted).lineLimit(2) }
                Button(active.isRest ? "结束休息" : "放弃") { model.abandon() }
                    .accessibilityLabel(active.isRest ? "结束休息" : "放弃本次")
                    .buttonStyle(.plain).font(.callout).foregroundColor(Ink.muted)
                    .padding(.top, 12).help("放弃后不留记录")
            } else {
                HStack(spacing: 10) {
                    ForEach([15, 25, 45], id: \.self) { minutes in
                        Button { model.preferences.focusMinutes = minutes } label: {
                            Text("\(minutes) 分钟")
                                .font(.system(size: 12))
                                .foregroundColor(model.preferences.focusMinutes == minutes ? Ink.primary : Ink.muted)
                                .padding(.horizontal, 16).frame(minHeight: 36)
                                .overlay(alignment: .bottom) {
                                    if model.preferences.focusMinutes == minutes {
                                        Rectangle().fill(Ink.accent.opacity(0.65)).frame(width: 18, height: 1)
                                    }
                                }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.preferences.focusMinutes == minutes ? [.isSelected] : [])
                    }
                }
                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        TextField("这一段想做什么", text: $label)
                            .textFieldStyle(.plain).font(.callout)
                            .accessibilityLabel("预期任务（可留空）").help("可留空")
                            .padding(.leading, 14).padding(.trailing, 8)
                        Rectangle().fill(Ink.line.opacity(0.6)).frame(width: 1, height: 16)
                        Button { choosingSound = true } label: {
                            HStack(spacing: 6) {
                                Text(model.preferences.sound.title)
                                Image(systemName: "chevron.down").font(.system(size: 8))
                            }.font(.system(size: 13)).foregroundColor(Ink.muted)
                                .frame(width: 64, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("选择环境音").accessibilityValue(model.preferences.sound.title)
                            .popover(isPresented: $choosingSound) {
                                VStack(spacing: 4) {
                                    ForEach(SoundChoice.ambientChoices, id: \.self) { sound in
                                        Button {
                                            model.preferences.sound = sound
                                            choosingSound = false
                                        } label: {
                                            HStack {
                                                Text(sound.title)
                                                Spacer()
                                                Image(systemName: "checkmark")
                                                    .opacity(model.preferences.sound == sound ? 1 : 0)
                                            }.font(.callout).foregroundColor(Ink.primary)
                                                .padding(.horizontal, 12).frame(height: 44)
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                            .accessibilityAddTraits(model.preferences.sound == sound ? [.isSelected] : [])
                                    }
                                }.padding(8).frame(width: 160).background(Ink.paper)
                            }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.line.opacity(0.7)).frame(height: 1)
                    }
                    Button { model.start(label: label) } label: {
                        Text("开始").font(.system(size: 16, weight: .regular, design: .serif)).tracking(3)
                            .frame(maxWidth: .infinity, minHeight: 22)
                    }.accessibilityLabel("开始专注").buttonStyle(ZenButtonStyle()).disabled(!model.canStart)
                }.frame(maxWidth: 300)
            }
        }.frame(maxWidth: .infinity).padding(.bottom, 48)
            .onChange(of: model.preferences) { _ in model.savePreferences() }
    }
    private var progress: Double {
        guard let active = model.active else { return 0 }
        return 1 - Double(model.remaining) / Double(active.targetSeconds)
    }
}

private struct RecordsView: View {
    @ObservedObject var model: ZenModel
    @State private var allDays = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("留痕").font(.system(size: 21, design: .serif))
                    Text("今天已记录 \(model.todaySeconds / 60) 分钟").font(.caption).foregroundColor(Ink.muted)
                }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("刷新本地文件")
            }
            if !model.drafts.isEmpty {
                Text("待补记").font(.caption).foregroundColor(Ink.muted)
                ForEach(model.drafts) { draft in
                    Button { model.editorID = draft.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(draft.record.title).lineLimit(2)
                                Text("\(draft.record.dayKey) · \(durationText(draft.record.focusedSeconds)) · \(draft.record.outcome.title)")
                                    .font(.caption).foregroundColor(Ink.muted)
                            }
                            Spacer(); Image(systemName: "square.and.pencil")
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            Toggle("查看全部日期", isOn: $allDays).font(.caption)
            if visibleRecords.isEmpty && model.drafts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "leaf").font(.system(size: 28, weight: .ultraLight))
                    Text("尚无记录，时间从下一次开始。").font(.callout)
                }.foregroundColor(Ink.muted).frame(maxWidth: .infinity).padding(.vertical, 44)
            }
            ForEach(visibleRecords) { item in
                Button { model.beginEditing(item) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Text(item.record.startedAt, style: .time).font(.system(size: 12, design: .monospaced)).foregroundColor(Ink.muted)
                            .frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.record.title).font(.callout).lineLimit(2)
                            Text("\(durationText(item.record.focusedSeconds)) · \(item.record.outcome.title)\(item.record.annotationStatus == .pending ? " · 待补记" : "")")
                                .font(.caption).foregroundColor(Ink.muted)
                            if allDays { Text(item.record.dayKey).font(.caption2).foregroundColor(Ink.muted) }
                            if model.conflicts.contains(item.id) { Text("文件有不同版本").font(.caption).foregroundColor(.orange) }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }.buttonStyle(.plain)
                Divider().overlay(Ink.line)
            }
            if !model.issues.isEmpty {
                DisclosureGroup("文件提示（\(model.issues.count)）") {
                    ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).textSelection(.enabled).padding(.vertical, 4) }
                }.font(.caption)
            }
        }
    }
    private var visibleRecords: [StoredRecord] {
        model.records.filter { item in
            (allDays || Calendar.current.isDateInToday(item.record.startedAt)) && !model.drafts.contains(where: { $0.id == item.id })
        }
    }
}

private struct PreferencesView: View {
    @ObservedObject var model: ZenModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("节奏") {
                Stepper("专注 \(model.preferences.focusMinutes) 分钟", value: $model.preferences.focusMinutes, in: 1...240)
                Stepper("休息 \(model.preferences.restMinutes) 分钟", value: $model.preferences.restMinutes, in: 1...60)
                Button("开始休息") { model.start(rest: true); model.selectedTab = 0 }
                    .disabled(!model.canStart)
                Text("时长修改从下一轮生效，每轮由你主动开始。").font(.caption).foregroundColor(Ink.muted)
            }
            settingsSection("陪伴声音") {
                Picker("陪伴声音", selection: $model.preferences.sound) {
                    ForEach(SoundChoice.ambientChoices, id: \.self) { Text($0.title).tag($0) }
                }
                HStack { Text("音量"); Slider(value: $model.preferences.volume, in: 0...1).accessibilityLabel("专注声音音量") }
                if model.preferences.sound == .wood {
                    Stepper("每 \(Int(model.preferences.woodInterval)) 秒一声", value: $model.preferences.woodInterval, in: 1...15, step: 1)
                    Text("真实木鱼录音，柔化敲击，伴随轻柔的空间余韵。").font(.caption).foregroundColor(Ink.muted)
                }
                if model.preferences.sound == .pine {
                    Text("松林风声录音，轻柔持续播放。").font(.caption).foregroundColor(Ink.muted)
                } else if model.preferences.sound == .rain {
                    Text("无雷声的细雨录音，轻柔持续播放。").font(.caption).foregroundColor(Ink.muted)
                }
                Button(model.isPreviewingSound ? "停止试听" : "试听 10 秒") { if model.isPreviewingSound { model.stopPreview() } else { model.previewSound() } }
                    .disabled(model.active != nil || model.preferences.sound == .silent)
                Text("陪伴声音在专注期间循环播放，结束时停止。").font(.caption).foregroundColor(Ink.muted)
            }
            settingsSection("结束提醒") {
                Toggle("结束时敲磬提醒", isOn: $model.preferences.completionSound)
                if model.preferences.completionSound {
                    HStack {
                        Text("提醒音量")
                        Slider(value: Binding(get: { model.preferences.completionVolume }, set: { model.preferences.reminderVolume = $0 }), in: 0...1)
                    }
                    Text("与背景声音量独立，静音专注也可在结束时提醒。").font(.caption).foregroundColor(Ink.muted)
                }
                Toggle("到时发送系统通知", isOn: $model.preferences.notificationEnabled)
                Button("允许通知") { Task { await model.requestNotifications() } }
                Text(model.notificationStatus).font(.caption).foregroundColor(Ink.muted)
                Text("提醒设置从下一轮生效。Mac 到时弹出本轮补记；iPhone 前台直接补记，后台点通知进入。").font(.caption).foregroundColor(Ink.muted)
            }
            settingsSection("本地文件") {
                Text(model.directory?.path ?? "尚未选择目录").font(.caption).foregroundColor(Ink.muted).textSelection(.enabled)
                DirectoryButton(model: model, title: model.directory == nil ? "选择数据文件夹" : "更换 / 重新授权目录").disabled(model.active != nil)
                #if os(macOS)
                Button("在 Finder 中打开") { model.revealDirectory() }.disabled(model.directory == nil)
                #endif
                Text("每段专注一份 Markdown。更换目录不会迁移历史，已有草稿保留。文件同步由你自己安排。").font(.caption).foregroundColor(Ink.muted)
            }
            #if os(macOS)
            settingsSection("快捷键") {
                shortcutRow("开始", key: $model.preferences.startKey, modifiers: $model.preferences.startModifiers)
                shortcutRow("放弃", key: $model.preferences.abandonKey, modifiers: $model.preferences.abandonModifiers)
                if let error = model.shortcutError { Text(error).font(.caption).foregroundColor(.orange) }
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
            }
            #endif
        }
        .onChange(of: model.preferences) { _ in model.savePreferences() }
        .onDisappear { model.stopPreview() }
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 17, weight: .medium, design: .serif)).padding(.bottom, 3)
            content().font(.callout)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    #if os(macOS)
    private func shortcutRow(_ title: String, key: Binding<UInt32>, modifiers: Binding<UInt32>) -> some View {
        HStack {
            Text(title)
            Picker("修饰键", selection: modifiers) {
                Text("⌃⌥").tag(UInt32(6144)); Text("⌘⇧").tag(UInt32(768)); Text("⌘⌥").tag(UInt32(2304))
            }.labelsHidden()
            Picker("按键", selection: key) {
                Text("空格").tag(UInt32(49)); Text("Esc").tag(UInt32(53)); Text("Z").tag(UInt32(6)); Text("F").tag(UInt32(3))
            }.labelsHidden()
        }
    }
    #endif
}

private struct DirectoryButton: View {
    @ObservedObject var model: ZenModel
    var title: String
    @State private var picking = false
    var body: some View {
        Button(title) { picking = true }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                switch result { case .success(let url): model.chooseDirectory(url); case .failure(let error): model.errorMessage = error.localizedDescription }
            }
    }
}

struct AnnotationView: View {
    @ObservedObject var model: ZenModel
    let id: UUID
    @State private var deleting = false
    @State private var moving = false
    @State private var details = false
    @FocusState private var contentFocused: Bool
    private var draft: EditDraft? { model.drafts.first { $0.id == id } }
    private func field(_ keyPath: WritableKeyPath<FocusRecord, String>) -> Binding<String> {
        Binding(get: { draft?.record[keyPath: keyPath] ?? "" }, set: { value in
            guard var d = draft else { return }; d.record[keyPath: keyPath] = value; model.updateDraft(d)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("这段时间做了什么？").font(.system(size: 20, design: .serif))
                    if let draft {
                        Text(durationText(draft.record.focusedSeconds) + (draft.record.outcome == .completed ? "" : " · " + draft.record.outcome.title))
                            .font(.caption).foregroundColor(Ink.muted)
                    }
                }
                Spacer()
                Button { model.editorID = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundColor(Ink.muted).accessibilityLabel("稍后补记").help("稍后补记")
            }
            if let draft {
                #if os(macOS)
                ComposingTextView(text: field(\.content), submit: { model.saveAnnotation(id) })
                    .frame(height: 125).padding(12).background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                #else
                TextEditor(text: field(\.content)).focused($contentFocused).frame(minHeight: 100, maxHeight: 140).padding(8)
                    .scrollContentBackground(.hidden).background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                #endif
                if details {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("备注与资料").font(.caption).foregroundColor(Ink.muted)
                        TextEditor(text: field(\.notes)).frame(height: 70)
                        TextField("文件路径或网址", text: field(\.reference)).textFieldStyle(.roundedBorder)
                    }
                }
                if let error = model.errorMessage { Text(error).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
                if draft.directoryPath != model.directory?.path {
                    Text("草稿属于其他目录。切回原目录可继续保存。").font(.caption).foregroundColor(Ink.muted)
                    Button("将这份草稿保存到当前目录…") { moving = true }.font(.caption)
                }
                HStack {
                    Menu {
                        Button(details ? "收起备注与资料" : "备注与资料") { details.toggle() }
                        Button("暂不填写") { model.saveAnnotation(id, skip: true) }
                        Divider()
                        Button("删除本次记录…", role: .destructive) { deleting = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundColor(Ink.muted).accessibilityLabel("更多操作")
                    Spacer()
                    Button("保存") { model.saveAnnotation(id) }.buttonStyle(ZenButtonStyle())
                        .accessibilityLabel("保存到本地").help("Enter 保存 · Shift + Enter 换行")
                }
            }
        }
        .padding(28).foregroundColor(Ink.primary).background(Ink.paper).tint(Ink.accent).preferredColorScheme(.light)
        #if os(macOS)
        .frame(width: 420)
        #endif
        .onAppear { contentFocused = true }
        .confirmationDialog("删除本次记录？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) { model.deleteRecord(id) }
            Button("保留", role: .cancel) {}
        } message: { Text("删除本地文件和对应草稿，此操作无法撤销。") }
        .confirmationDialog("保存草稿到当前目录？", isPresented: $moving, titleVisibility: .visible) {
            Button("保存到当前目录") { model.moveDraftToCurrentDirectory(id); model.saveAnnotation(id) }
            Button("取消", role: .cancel) {}
        } message: { Text("原目录中的历史文件会保留。") }
    }
}

private struct ZenButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium)).foregroundColor(Ink.primary)
            .padding(.horizontal, 22).padding(.vertical, 13)
            .background(Ink.accent.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.accent.opacity(0.2), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

#if os(macOS)
struct ComposingTextView: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = Editor(); editor.delegate = context.coordinator; editor.submit = submit
        editor.isRichText = false; editor.drawsBackground = false; editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.string = text; scroll.documentView = editor
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? Editor else { return }
        editor.submit = submit
        if !editor.hasMarkedText(), editor.string != text { editor.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposingTextView
        init(_ parent: ComposingTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
    final class Editor: NSTextView {
        var submit: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(), !event.modifierFlags.contains(.shift) {
                submit?(); return
            }
            super.keyDown(with: event)
        }
    }
}

public struct ZenMenuView: View {
    @ObservedObject var model: ZenModel
    @Environment(\.openWindow) private var openWindow
    public init(model: ZenModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("禅").font(.system(size: 25, design: .serif)); Spacer(); Text(model.active == nil ? "此刻闲静" : model.active?.isRest == true ? "歇息中" : "专注中").font(.caption).foregroundColor(Ink.muted) }
            if model.active != nil {
                Text(durationText(model.remaining)).font(.system(size: 38, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Button(model.active?.isRest == true ? "结束休息" : "放弃本次") { model.abandon() }
            } else {
                Button("开始专注 · \(model.preferences.focusMinutes) 分钟") {
                    if model.directory == nil { show(tab: 2) } else { model.start() }
                }.buttonStyle(ZenButtonStyle())
                if !model.recentNames.isEmpty {
                    Menu("最近使用") { ForEach(model.recentNames, id: \.self) { name in Button(name) { model.start(label: name) } } }
                }
                Button("休息 \(model.preferences.restMinutes) 分钟") { model.start(rest: true) }.disabled(!model.canStart)
            }
            if model.pendingCount > 0 { Button("待补记 · \(model.pendingCount)") { show(tab: 1); model.showPending() } }
            if model.errorMessage != nil { Text("有内容未保存，请打开主窗口查看。").font(.caption).foregroundColor(.orange) }
            Divider()
            HStack { Button("今天的记录") { show(tab: 1) }; Spacer(); Button("设置") { show(tab: 2) } }
            HStack { Button("打开禅") { show(tab: 0) }; Spacer(); Button("退出") { NSApp.terminate(nil) } }
        }.padding(22).frame(width: 300).foregroundColor(Ink.primary).background(Ink.paper).tint(Ink.accent).preferredColorScheme(.light)
    }
    private func show(tab: Int) {
        model.selectedTab = tab; openWindow(id: "zen"); NSApp.activate(ignoringOtherApps: true)
        model.openWindow = { openWindow(id: "zen"); NSApp.activate(ignoringOtherApps: true) }
    }
}
#endif
