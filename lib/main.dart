import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'providers/match_provider.dart';
import 'server/local_server.dart';
import 'models/game.dart';
import 'ui/web/remote_control.dart';
import 'ui/web/web_helper.dart';
import 'ui/mobile/mobile_remote.dart';

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
    registerIframeViewFactory();
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Telecomando',
      home: RemoteControlScreen(),
    ));
    
  } else if (Platform.isAndroid || Platform.isIOS) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arbitro Mobile',
      home: MobileRemoteScreen(),
    ));
    
  } else {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(size: Size(1280, 720), center: true, title: "Tabellone Segnapunti");
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false); 
      await windowManager.setFullScreen(true);
    });

    final matchProvider = MatchProvider();
    await matchProvider.loadFromFile();
    
    await startLocalServer(matchProvider);
    await matchProvider.initWebRTC();

    runApp(
      ChangeNotifierProvider.value(
        value: matchProvider,
        child: const MaterialApp(debugShowCheckedModeBanner: false, home: ScoreboardApp()),
      ),
    );
  }
}

class ScoreboardApp extends StatelessWidget {
  const ScoreboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MatchProvider>();

    // --- CALCOLO TITOLI CONDIVISO PER ENTRAMBE LE VISTE ---
    bool isTotals = state.currentPage == 'totals';
    String mainTitle = state.eventName;
    String subtitle = 'CLASSIFICA GENERALE';
    Game? currentGame;

    if (!isTotals) {
      int? gameIndex = int.tryParse(state.currentPage);
      if (gameIndex != null && gameIndex >= 0 && gameIndex < state.games.length) {
        currentGame = state.games[gameIndex];
        subtitle = currentGame.name.toUpperCase();
      }
    }

    Widget mainContent;

    if (state.isTimerVisible) {
      // --- VISTA TIMER CON TITOLI INCLUSI ---
      String m = (state.timerSeconds ~/ 60).toString().padLeft(2, '0');
      String s = (state.timerSeconds % 60).toString().padLeft(2, '0');
      Color timerColor = state.timerSeconds <= 10 ? Colors.redAccent : Colors.white;

      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                child: Text(
                  mainTitle,
                  style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3, shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]),
                ),
              ),
              FittedBox(
                child: Text(
                  subtitle,
                  style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5),
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50.0),
                    child: Text(
                      "$m:$s",
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                        color: timerColor,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 40, offset: Offset(0, 10))]
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // --- VISTA NORMALE TABELLONE SQUADRE ---
      List<Widget> teamCardWidgets = [];
      if (state.teams.isNotEmpty) {
        if (state.isRevealMode) {
          List<int> sortedIndices = List.generate(state.teams.length, (i) => i);
          sortedIndices.sort((a, b) {
            int scoreA = isTotals ? state.getTotalScore(a) : (currentGame?.scores[a] ?? 0);
            int scoreB = isTotals ? state.getTotalScore(b) : (currentGame?.scores[b] ?? 0);
            return scoreA.compareTo(scoreB);
          });

          for (int i = 0; i < sortedIndices.length; i++) {
            int originalIndex = sortedIndices[i];
            final team = state.teams[originalIndex];
            int score = isTotals ? state.getTotalScore(originalIndex) : (currentGame?.scores[originalIndex] ?? 0);
            bool showJolly = isTotals ? team.hasUsedJolly : (currentGame?.activeJollies[originalIndex] ?? false);
            String? partial;
            if (!isTotals) {
              partial = currentGame?.partials[originalIndex];
              if (partial == null || partial.isEmpty) partial = null;
            }

            if (i < state.revealedTeamsCount) {
              teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, key: ValueKey('team_${originalIndex}_revealed')))));
            } else {
              int rank = state.teams.length - i; 
              teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildObscuredCard(rank))));
            }
          }
        } else {
          for (int i = 0; i < state.teams.length; i++) {
            final team = state.teams[i];
            int score = isTotals ? state.getTotalScore(i) : (currentGame?.scores[i] ?? 0);
            bool showJolly = isTotals ? team.hasUsedJolly : (currentGame?.activeJollies[i] ?? false);
            String? partial;
            if (!isTotals) {
              partial = currentGame?.partials[i];
              if (partial == null || partial.isEmpty) partial = null;
            }
            teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, key: ValueKey('team_$i')))));
          }
        }
      }

      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                child: Text(
                  mainTitle,
                  style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3, shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]),
                ),
              ),
              FittedBox(
                child: Text(
                  subtitle,
                  style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5),
                ),
              ),
              const SizedBox(height: 60),
              
              if (state.teams.isEmpty)
                const Text("In attesa delle squadre...", style: TextStyle(color: Colors.white54, fontSize: 30))
              else
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: teamCardWidgets, 
                  ),
                ),
            ],
          ),
        ),
      );
    } 

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Stack(
          children: [
            mainContent,
            
            if (state.isRendererReady)
              Positioned.fill(
                child: Offstage(
                  offstage: !state.isStreamingActive,
                  child: Container(
                    color: Colors.black,
                    child: RTCVideoView(
                      state.renderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly, {Key? key}) {
    Color teamColor = Colors.white;
    try { teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000); } catch (e) {}

    return Container(
      key: key, 
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: teamColor.withOpacity(0.8), width: 4),
        boxShadow: [BoxShadow(color: teamColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)]
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name.toUpperCase(), style: TextStyle(fontSize: 50, color: teamColor, fontWeight: FontWeight.bold, letterSpacing: 2)),
                if (showJolly)
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.orange, blurRadius: 10, spreadRadius: 2)]),
                    child: const Text('🌟 JOLLY', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
              ],
            ),
          ),
          
          if (partial != null) ...[
            const SizedBox(height: 10), 
            FittedBox(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(15)),
                child: Text(
                  partial,
                  style: const TextStyle(fontSize: 35, color: Colors.cyanAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 30),
          
          Expanded(
            child: FittedBox(
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: score),
                duration: const Duration(milliseconds: 1200), 
                curve: Curves.easeOutCubic, 
                builder: (context, value, child) {
                  if (value == 0) return const SizedBox.shrink(); 
                  return Text(value.toString(), style: const TextStyle(fontSize: 250, fontWeight: FontWeight.w900, color: Colors.white));
                }
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObscuredCard(int rank) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white54, width: 4),
      ),
      child: Center(
        child: FittedBox(
          child: Text(
            "$rank°", 
            style: const TextStyle(fontSize: 150, color: Colors.white54, fontWeight: FontWeight.bold)
          )
        )
      )
    );
  }
}