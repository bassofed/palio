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
            // Passiamo un Key univoco per assicurarci che l'animazione parta ogni volta che il widget viene "scoperto"
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
        ),
      ),
    );
  }

  // Aggiungiamo un parametro Key opzionale per forzare il rebuilding
  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly, {Key? key}) {
    Color teamColor = Colors.white;
    try { teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000); } catch (e) {}

    return Container(
      key: key, // Assegniamo la key al container principale
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
                // TRUCCO: Impostiamo SEMPRE begin a 0.
                // Quando il widget viene disegnato per la prima volta (es. rivelato), partirà da 0 e andrà al punteggio reale.
                // Se aggiorni il punteggio dal telecomando senza nascondere la squadra, Flutter (essendo intelligente) 
                // ottimizzerà l'animazione e scalerà dal numero visibile precedente al nuovo numero, 
                // mantenendo la fluidità durante l'assegnazione dei punti live.
                tween: IntTween(begin: 0, end: score),
                // Aumentiamo leggermente la durata a 1.2 secondi per enfatizzare l'effetto "contatore che sale"
                duration: const Duration(milliseconds: 1200), 
                curve: Curves.easeOutCubic, // Aggiungiamo una curva per rallentare dolcemente alla fine
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