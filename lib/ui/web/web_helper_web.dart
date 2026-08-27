// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

void registerIframeViewFactory() {
  ui.platformViewRegistry.registerViewFactory(
    'webrtc-receiver-view',
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = 'stream_receiver.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    },
  );
}

void redirectToBroadcaster(String origin) {
  html.window.location.href = '$origin/stream_broadcaster.html';
}
