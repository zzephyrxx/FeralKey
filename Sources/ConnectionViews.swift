// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

struct ConnectionSettingsView: View {
    @ObservedObject var model: LabModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("连接与权限").font(.system(size:22,weight:.semibold))
                Spacer(); Button("完成") { dismiss() }
            }
            Text(model.status).font(.system(size:12)).foregroundStyle(model.theme.secondary)
            permission("输入监控",detail:"控制键盘",allowed:model.inputPermissionGranted) { model.permissions() }
            permission("辅助功能",detail:"系统通知联动",allowed:model.accessibilityPermissionGranted) { model.accessibilityPermissions() }
            permission("系统音频",detail:"音乐律动",allowed:model.audioPermissionGranted) { model.audioPermissions() }
            Divider()
            Toggle("打开应用后自动连接",isOn:$model.autoConnect)
            Toggle("连接后恢复上次设置",isOn:$model.restoreOnConnect)
            Picker("动态帧率",selection:Binding(get:{ model.motionFPS },set:{ model.setMotionFPS($0) })) {
                ForEach(LightingRate.choices,id:\.self) { Text("\($0) FPS").tag($0) }
            }.frame(width:230).help("运行时直接生效；实际帧率取决于 USB 和键盘响应速度。")
            Text("灯光、通知、额度区和快捷键设置自动保存。音乐律动每次打开后手动启用；完整改键不会自动重写。")
                .font(.system(size:11)).foregroundStyle(model.theme.secondary)
            HStack {
                Button("显示当前应用位置") { model.revealApplication() }
                Spacer()
                Button(model.connected ? "重新连接" : "连接键盘") { model.connect() }
                    .buttonStyle(FeralButtonStyle(theme:model.theme,prominent:true))
            }
            FeralDisclosure("授权后仍无法连接",theme:model.theme,symbol:"lock.shield") {
                Text("系统权限需你手动允许。当前为临时签名：更新构建后若旧权限失效，请退出 FeralKey，移除旧权限条目并添加当前这份应用，再重新打开。")
                    .font(.system(size:11)).foregroundStyle(model.theme.secondary)
            }.font(.system(size:11))
        }.font(.system(size:12)).padding(26).frame(width:510)
            .background(GlassBackdrop(theme:model.theme)).foregroundStyle(model.theme.foreground)
            .buttonStyle(FeralButtonStyle(theme:model.theme)).preferredColorScheme(model.theme.scheme)
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in model.objectWillChange.send() }
    }
    private func permission(_ title:String,detail:String,allowed:Bool,action:@escaping ()->Void) -> some View {
        HStack {
            Image(systemName:allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? model.theme.accent : model.theme.secondary)
            Text(title); Text(detail).foregroundStyle(model.theme.secondary)
            Spacer(); Button(allowed ? "查看" : "去授权",action:action)
        }
    }
}
