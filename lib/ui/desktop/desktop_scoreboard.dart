import 'dart:math';
import 'dart:ui';
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
      int? gameId = int.tryParse(state.currentPage);
      if (gameId != null) {
        // Cerchiamo il gioco per ID univoco, non per posizione nell'array!
        final index = state.games.indexWhere((g) => g.id == gameId);
        if (index != -1) {
          currentGame = state.games[index];
          subtitle = currentGame.name.toUpperCase();
        }
      }
    }

    // --- LOGICA DI ORDINAMENTO CORRETTA (USA TEAM ID, NON INDEX) ---
    List<int> sortedIndices = List.generate(state.teams.length, (i) => i);
    if (state.teams.isNotEmpty) {
      sortedIndices.sort((a, b) {
        final teamA = state.teams[a];
        final teamB = state.teams[b];
        
        int scoreA = isTotals 
            ? state.getTotalScore(teamA.id) 
            : ((currentGame?.scores[teamA.id.toString()] as num?)?.toInt() ?? 0);
            
        int scoreB = isTotals 
            ? state.getTotalScore(teamB.id) 
            : ((currentGame?.scores[teamB.id.toString()] as num?)?.toInt() ?? 0);
            
        return scoreA.compareTo(scoreB);
      });
    }

    bool isWinnerRevealed = isTotals && state.isRevealMode && state.teams.isNotEmpty && state.revealedTeamsCount == state.teams.length;

    if (isWinnerRevealed && !_hasFiredConfetti) {
      _hasFiredConfetti = true;
      _confettiController.play();
    } else if (!isWinnerRevealed && _hasFiredConfetti) {
      _hasFiredConfetti = false;
      _confettiController.stop();
    }

    List<Color> confettiColors = [Colors.white];
    if (isWinnerRevealed && state.teams.isNotEmpty) {
      try {
        Color winnerColor = Color(int.parse(state.teams[sortedIndices.last].colorHex.substring(1), radix: 16) + 0xFF000000);
        confettiColors = [winnerColor, winnerColor, Colors.white]; 
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
          
          // --- ESTRAZIONE DATI CORRETTA TRAMITE TEAM.ID ---
          int score = isTotals 
              ? state.getTotalScore(team.id) 
              : ((currentGame?.scores[team.id.toString()] as num?)?.toInt() ?? 0);
              
          bool showJolly = isTotals 
              ? team.hasUsedJolly 
              : (currentGame?.activeJollies[team.id] ?? false);
          
          bool isParticipating = true;
          if (!isTotals) {
            isParticipating = currentGame?.participations[team.id.toString()] ?? true;
          }

          String? partial;
          if (!isTotals) {
            partial = currentGame?.partials[team.id.toString()];
            if (partial == null || partial.isEmpty) partial = null;
          }

          int rank = state.teams.length - i;
          bool isWinner = isTotals && rank == 1;

          Widget cardContent;
          if (state.isRevealMode) {
            if (i < state.revealedTeamsCount) {
              cardContent = _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, isWinner: isWinnerRevealed && isWinner, isParticipating: isParticipating);
            } else {
              cardContent = _buildObscuredCard(rank);
            }
          } else {
            cardContent = _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, isWinner: false, isParticipating: isParticipating);
          }

          teamCardWidgets.add(
            Expanded(
              child: AnimatedOpacity(
                opacity: !isParticipating ? 0.3 : (isWinnerRevealed ? (isWinner ? 1.0 : 0.3) : 1.0),
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

  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly, {bool isWinner = false, bool isParticipating = true}) {
    Color teamColor = Colors.white;
    try { teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000); } catch (e) {}

    return AnimatedContainer(
      duration: const Duration(milliseconds: 1000),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: teamColor.withOpacity(0.8), 
          width: isWinner ? 8 : 4
        ),
        boxShadow: [
          if (isWinner) BoxShadow(color: teamColor.withOpacity(0.6), blurRadius: 60, spreadRadius: 15),
          if (!isWinner && isParticipating) BoxShadow(color: teamColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)
        ]
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name.toUpperCase(), style: TextStyle(fontSize: 50, color: teamColor, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ],
            ),
          ),

          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showJolly && isParticipating)
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.orange, blurRadius: 10, spreadRadius: 2)]),
                    child: const Text('🌟 JOLLY', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
              ],
            ),
          ),
          
          if (partial != null && isParticipating) ...[
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
              child: isParticipating 
                ? TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: score),
                    duration: const Duration(milliseconds: 1200), 
                    curve: Curves.easeOutCubic, 
                    builder: (context, value, child) {
                      //if (value == 0 && score != 0) return const SizedBox.shrink(); 
                      return Text(
                        value.toString().padLeft(2, ' '), 
                        style: const TextStyle(fontSize: 250, fontWeight: FontWeight.w900, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])
                      );
                    }
                  )
                : const Text("-", style: TextStyle(fontSize: 250, fontWeight: FontWeight.w900, color: Colors.white54)),
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