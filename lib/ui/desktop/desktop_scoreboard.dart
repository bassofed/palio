import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:confetti/confetti.dart';

import '../../providers/match_provider.dart';
import '../../models/game.dart';

class ScoreboardApp extends StatefulWidget {
  const ScoreboardApp({super.key});

  @override
  State<ScoreboardApp> createState() => _ScoreboardAppState();
}

class _ScoreboardAppState extends State<ScoreboardApp> {
  late ConfettiController _confettiController;
  bool _hasFiredConfetti = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 10));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

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

    // --- CALCOLO VINCITORE E CLASSIFICA ---
    List<int> sortedIndices = List.generate(state.teams.length, (i) => i);
    if (state.teams.isNotEmpty) {
      sortedIndices.sort((a, b) {
        int scoreA = isTotals ? state.getTotalScore(a) : (currentGame?.scores[a] ?? 0);
        int scoreB = isTotals ? state.getTotalScore(b) : (currentGame?.scores[b] ?? 0);
        return scoreA.compareTo(scoreB);
      });
    }

    // L'effetto si attiva SOLO nei Totali (isTotals == true) 
    // e quando tutte le squadre sono rivelate.
    bool isWinnerRevealed = isTotals && state.isRevealMode && state.teams.isNotEmpty && state.revealedTeamsCount == state.teams.length;

    if (isWinnerRevealed && !_hasFiredConfetti) {
      _hasFiredConfetti = true;
      _confettiController.play();
    } else if (!isWinnerRevealed && _hasFiredConfetti) {
      _hasFiredConfetti = false;
      _confettiController.stop();
    }

    // I coriandoli ora usano il colore della contrada vincente (con un po' di bianco)
    List<Color> confettiColors = [Colors.white];
    if (isWinnerRevealed && state.teams.isNotEmpty) {
      try {
        Color winnerColor = Color(int.parse(state.teams[sortedIndices.last].colorHex.substring(1), radix: 16) + 0xFF000000);
        confettiColors = [winnerColor, winnerColor, Colors.white]; // Doppia dose del colore di fazione!
      } catch (e) {}
    }

    Widget mainContent;

    if (state.isTimerVisible) {
      String m = (state.timerSeconds ~/ 60).toString().padLeft(2, '0');
      String s = (state.timerSeconds % 60).toString().padLeft(2, '0');
      Color timerColor = state.timerSeconds <= 10 ? Colors.redAccent : Colors.white;

      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(child: Text(mainTitle, style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3, shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]))),
              FittedBox(child: Text(subtitle, style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5))),
              const SizedBox(height: 40),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50.0),
                    child: Text("$m:$s", style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: timerColor, shadows: const [Shadow(color: Colors.black, blurRadius: 40, offset: Offset(0, 10))])),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      List<Widget> teamCardWidgets = [];
      
      if (state.teams.isNotEmpty) {
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

          int rank = state.teams.length - i;
          // Segnamo come "vincitore" la carta solo se siamo nei totali
          bool isWinner = isTotals && rank == 1;

          Widget cardContent;
          if (state.isRevealMode) {
            if (i < state.revealedTeamsCount) {
              cardContent = _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, isWinner: isWinnerRevealed && isWinner);
            } else {
              cardContent = _buildObscuredCard(rank);
            }
          } else {
            cardContent = _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, isWinner: false);
          }

          teamCardWidgets.add(
            Expanded(
              child: AnimatedOpacity(
                opacity: isWinnerRevealed ? (isWinner ? 1.0 : 0.3) : 1.0,
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
                child: AnimatedScale(
                  scale: isWinnerRevealed ? (isWinner ? 1.15 : 0.85) : 1.0,
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.elasticOut, 
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: cardContent,
                  ),
                ),
              ),
            ),
          );
        }
      }

      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(child: Text(mainTitle, style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3, shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]))),
              FittedBox(child: Text(subtitle, style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5))),
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
            
            Align(
              alignment: Alignment.topLeft,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: pi / 4, 
                emissionFrequency: 0.05,
                numberOfParticles: 20,
                maxBlastForce: 80,
                minBlastForce: 40,
                gravity: 0.2,
                colors: confettiColors,
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: 3 * pi / 4, 
                emissionFrequency: 0.05,
                numberOfParticles: 20,
                maxBlastForce: 80,
                minBlastForce: 40,
                gravity: 0.2,
                colors: confettiColors,
              ),
            ),
            
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

  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly, {bool isWinner = false}) {
    Color teamColor = Colors.white;
    try { teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000); } catch (e) {}

    return AnimatedContainer(
      duration: const Duration(milliseconds: 1000),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        // Il bordo rimane del colore della fazione, ma diventa più spesso
        border: Border.all(
          color: teamColor.withOpacity(0.8), 
          width: isWinner ? 8 : 4
        ),
        boxShadow: [
          // Il bagliore esplode usando il colore puro della contrada!
          if (isWinner) BoxShadow(color: teamColor.withOpacity(0.6), blurRadius: 60, spreadRadius: 15),
          if (!isWinner) BoxShadow(color: teamColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)
        ]
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Il testo rimane del colore della contrada
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
                child: Text(partial, style: const TextStyle(fontSize: 35, color: Colors.cyanAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
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
                  if (value == 0 && score != 0) return const SizedBox.shrink(); 
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
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white54, width: 4)),
      child: Center(child: FittedBox(child: Text("$rank°", style: const TextStyle(fontSize: 150, color: Colors.white54, fontWeight: FontWeight.bold)))),
    );
  }
}