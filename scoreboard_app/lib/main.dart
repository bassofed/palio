import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/match_provider.dart';
import 'server/local_server.dart';
import 'models/game.dart';
import 'ui/web/remote_control.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Telecomando',
      home: RemoteControlScreen(),
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
    
    // CARICAMENTO AUTOMATICO DEI DATI SALVATI PRIMA DI APRIRE L'APP
    await matchProvider.loadFromFile();

    await startLocalServer(matchProvider);

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

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Text(
                    mainTitle,
                    style: const TextStyle(
                      fontSize: 80, 
                      color: Colors.white, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]
                    ),
                  ),
                ),
                FittedBox(
                  child: Text(
                    subtitle,
                    style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5),
                  ),
                ),
                const SizedBox(height: 60),
                
                // Se non ci sono squadre, mostriamo un messaggio di attesa
                if (state.teams.isEmpty)
                  const Text("In attesa delle squadre...", style: TextStyle(color: Colors.white54, fontSize: 30))
                else
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(state.teams.length, (index) {
                        final team = state.teams[index];
                        int score = isTotals ? state.getTotalScore(index) : (currentGame?.scores[index] ?? 0);
                        
                        bool showJolly = isTotals ? team.hasUsedJolly : (currentGame?.activeJollies[index] ?? false);

                        String? partial;
                        if (!isTotals) {
                          partial = currentGame?.partials[index];
                          if (partial == null || partial.isEmpty) partial = null;
                        }

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10.0),
                            child: _buildTeamCard(team.name, team.colorHex, score, partial, showJolly),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly) {
    Color teamColor = Colors.white;
    try {
      teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {}

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: teamColor.withOpacity(0.8), width: 4),
        boxShadow: [
          BoxShadow(
            color: teamColor.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 5,
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.toUpperCase(), 
                  style: TextStyle(fontSize: 50, color: teamColor, fontWeight: FontWeight.bold, letterSpacing: 2)
                ),
                if (showJolly)
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.orange, blurRadius: 10, spreadRadius: 2)]
                    ),
                    child: const Text('🌟 JOLLY', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          
          Expanded(
            child: FittedBox(
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: score, end: score),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Text(
                    value.toString(),
                    style: const TextStyle(fontSize: 250, fontWeight: FontWeight.w900, color: Colors.white),
                  );
                }
              ),
            ),
          ),
          
          if (partial != null) ...[
            const SizedBox(height: 20),
            FittedBox(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
                child: Text(
                  partial,
                  style: const TextStyle(fontSize: 50, color: Colors.cyanAccent, fontFamily: 'Courier'),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}