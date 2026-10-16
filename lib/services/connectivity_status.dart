import 'dart:io' show Platform, File;

import 'package:connectivity_plus/connectivity_plus.dart';

/// 当前网络形态的折叠视图：是否在线、是否计费链路（非 WiFi/以太网）。
/// 官方 `showWifiCheckDialog` 的启动门与 `onNetChangeCheck` 的运行中
/// 自动暂停都吃这两个布尔。
typedef ConnectivityView = ({bool online, bool metered});

ConnectivityView foldConnectivity(List<ConnectivityResult> results) {
  var online = false;
  var metered = false;
  for (final result in results) {
    if (result == ConnectivityResult.none) continue;
    online = true;
    if (result != ConnectivityResult.wifi &&
        result != ConnectivityResult.ethernet) {
      metered = true;
    }
  }
  return (online: online, metered: online && metered);
}

Future<ConnectivityView> currentConnectivity() async {
  // Linux 桌面插件走 NetworkManager + system dbus；在没有 system dbus 的
  // 环境（沙箱/部分发行版）插件内部会游离出连接错误，外层 catch 捕获不到。
  // 直接按在线处理，避免触发插件。真实 Windows 走系统网络 API，不受影响。
  if (Platform.isLinux && !File('/var/run/dbus/system_bus_socket').existsSync()) {
    return (online: true, metered: false);
  }
  try {
    return foldConnectivity(await Connectivity().checkConnectivity());
  } catch (_) {
    // 平台通道不可用（测试宿主/异常设备）：按在线且不计费处理——
    // 宁可少问一次流量确认，也不让下载入口被误关死。
    return (online: true, metered: false);
  }
}
