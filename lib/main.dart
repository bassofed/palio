import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

// --- AGGIUNTO PER APRIRE IL BROWSER IN AUTOMATICO ---
import 'package:url_launcher/url_launcher.dart'; 

import 'providers/match_provider.dart';
import 'server/local_server.dart';
import 'ui/web/remote_control.dart';
import 'ui/web/web_helper.dart';
import 'ui/mobile/mobile_remote.dart';
import 'ui/desktop/desktop_scoreboard.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  HttpOverrides.global = MyHttpOverrides();

  if (kIsWeb) {
    // 1. COMPILAZIONE WEB -> Telecomando Completo
    registerIframeViewFactory();
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Telecomando',
      home: RemoteControlScreen(),
    ));
    
  } else if (Platform.isAndroid || Platform.isIOS) {
    // 2. COMPILAZIONE MOBILE -> Telecomando Semplificato Nativo
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arbitro Mobile',
      home: MobileRemoteScreen(),
    ));
    
  } else {
    // 3. COMPILAZIONE DESKTOP -> Tabellone Maxischermo Server
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720), 
      center: true, 
      title: "Tabellone Segnapunti"
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false); 
      await windowManager.setFullScreen(true);
    });

    final matchProvider = MatchProvider();
    await matchProvider.loadFromFile();
    
    // Accendiamo il Server e il WebRTC
    await startLocalServer(matchProvider);
    await matchProvider.initWebRTC();

    // =========================================================
    // TRUCCO: APRIAMO IL TELECOMANDO NEL BROWSER IN AUTOMATICO!
    // =========================================================
    Future.delayed(const Duration(seconds: 2), () async {
      // Usiamo l'indirizzo IP locale del PC stesso
      final url = Uri.parse('https://127.0.0.1:8080'); 
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    });
    // =========================================================

    runApp(
      ChangeNotifierProvider.value(
        value: matchProvider,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false, 
          home: ScoreboardApp() 
        ),
      ),
    );
  }
}