import 'dart:convert';
import 'dart:io';
import 'dart:async'; // Aggiunto per il Timer
import 'package:flutter/material.dart';
import '../models/team.dart';
import '../models/game.dart';

class MatchProvider extends ChangeNotifier {
  List<Team> teams = [];
  List<Game> games = [];
  String currentPage = 'totals';
  String eventName = 'GRANDE EVENTO 2026';

  bool isRevealMode = false;
  int revealedTeamsCount = 0;
  bool isStreamingActive = false;

  // --- STATO DEL COUNTDOWN ---
  bool isTimerVisible = false;
  int timerSeconds = 300; // Tempo attuale (es. 5 min = 300)
  int initialTimerSeconds = 300; // Tempo salvato per il reset
  bool isTimerRunning = false;
  Timer? _countdownTimer;

  final String _saveFileName = 'scoreboard_backup.json';

  Future<void> loadFromFile() async {
    try {
      final file = File(_saveFileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        
        eventName = data['eventName'] ?? 'GRANDE EVENTO 2026';
        currentPage = data['currentPage'] ?? 'totals';
        isRevealMode = data['isRevealMode'] ?? false;
        revealedTeamsCount = data['revealedTeamsCount'] ?? 0;
        
        isTimerVisible = data['isTimerVisible'] ?? false;
        timerSeconds = data['timerSeconds'] ?? 300;
        initialTimerSeconds = data['initialTimerSeconds'] ?? 300;
        isTimerRunning = false; // Il timer parte sempre fermo al riavvio
        
        if (data['teams'] != null) {
          teams = (data['teams'] as List).map((t) => Team.fromJson(t)).toList();
        }
        if (data['games'] != null) {
          games = (data['games'] as List).map((g) => Game.fromJson(g)).toList();
        }
        notifyListeners();
      }
    } catch (e) {
      print("⚠️ Errore caricamento: $e");
    }
  }

  void _autoSave() {
    try {
      final data = {
        'eventName': eventName,
        'currentPage': currentPage,
        'isRevealMode': isRevealMode,
        'revealedTeamsCount': revealedTeamsCount,
        'isTimerVisible': isTimerVisible,
        'timerSeconds': timerSeconds,
        'initialTimerSeconds': initialTimerSeconds,
        'teams': teams.map((t) => t.toJson()).toList(),
        'games': games.map((g) => g.toJson()).toList(),
      };
      File(_saveFileName).writeAsString(jsonEncode(data));
      notifyListeners(); 
    } catch (e) {}
  }

  // --- FUNZIONI COUNTDOWN ---
  void toggleTimerVisibility(bool visible) {
    isTimerVisible = visible;
    _autoSave();
  }

  void setTimer(int minutes, int seconds) {
    initialTimerSeconds = (minutes * 60) + seconds;
    timerSeconds = initialTimerSeconds;
    stopTimer();
    _autoSave();
  }

  void startTimer() {
    if (!isTimerRunning && timerSeconds > 0) {
      isTimerRunning = true;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timerSeconds > 0) {
          timerSeconds--;
          notifyListeners(); // Aggiorna solo UI, non salviamo su disco ogni singolo secondo per non usurare il drive
        } else {
          stopTimer();
        }
      });
      notifyListeners();
    }
  }

  void stopTimer() {
    isTimerRunning = false;
    _countdownTimer?.cancel();
    notifyListeners();
  }

  void resetTimer() {
    stopTimer();
    timerSeconds = initialTimerSeconds;
    _autoSave();
  }
  // ---------------------------

  void setStreamingActive(bool value) {
    isStreamingActive = value;
    notifyListeners();
  }

  void toggleRevealMode(bool enable) {
    isRevealMode = enable;
    if (!enable) revealedTeamsCount = 0;
    _autoSave();
  }

  void revealNext() {
    if (revealedTeamsCount < teams.length) revealedTeamsCount++;
    _autoSave();
  }

  void revealPrev() {
    if (revealedTeamsCount > 0) revealedTeamsCount--;
    _autoSave();
  }

  void setEventName(String name) {
    eventName = name;
    _autoSave();
  }

  void addGame(String name) {
    final newGame = Game(name: name);
    for (int i = 0; i < teams.length; i++) {
      newGame.scores[i] = 0;
      newGame.partials[i] = "";
      newGame.activeJollies[i] = false;
    }
    games.add(newGame);
    _autoSave();
  }

  void addTeam(String name, String colorHex) {
    teams.add(Team(name: name, colorHex: colorHex));
    int newIndex = teams.length - 1;
    for (var game in games) {
      game.scores[newIndex] = 0;
      game.partials[newIndex] = "";
      game.activeJollies[newIndex] = false;
    }
    _autoSave();
  }

  void removeGame(int index) {
    if (index >= 0 && index < games.length) {
      games.removeAt(index);
      bool pageChanged = false;
      if (currentPage == index.toString()) {
        currentPage = 'totals';
        pageChanged = true;
      } else {
        int? curr = int.tryParse(currentPage);
        if (curr != null && curr > index) {
          currentPage = (curr - 1).toString();
          pageChanged = true;
        }
      }
      if (pageChanged && isRevealMode) revealedTeamsCount = 0;
      _autoSave();
    }
  }

  void removeTeam(int index) {
    if (index >= 0 && index < teams.length) {
      teams.removeAt(index);
      for (var game in games) {
        var newScores = <int, int>{};
        var newPartials = <int, String>{};
        var newJollies = <int, bool>{};
        for (int i = 0; i <= teams.length; i++) {
          if (i == index) continue;
          int newKey = i > index ? i - 1 : i;
          if (game.scores.containsKey(i)) newScores[newKey] = game.scores[i]!;
          if (game.partials.containsKey(i)) newPartials[newKey] = game.partials[i]!;
          if (game.activeJollies.containsKey(i)) newJollies[newKey] = game.activeJollies[i]!;
        }
        game.scores = newScores;
        game.partials = newPartials;
        game.activeJollies = newJollies;
      }
      if (revealedTeamsCount > teams.length) revealedTeamsCount = teams.length;
      _autoSave();
    }
  }

  void resetGameScores(int index) {
    if (index >= 0 && index < games.length) {
      for (int i = 0; i < teams.length; i++) {
        games[index].scores[i] = 0;
        games[index].partials[i] = "";
        if (games[index].activeJollies[i] == true) {
          teams[i].hasUsedJolly = false;
        }
        games[index].activeJollies[i] = false;
      }
      _autoSave();
    }
  }

  void resetAll() {
    teams.clear();
    games.clear();
    eventName = 'NUOVO EVENTO';
    currentPage = 'totals';
    isRevealMode = false;
    revealedTeamsCount = 0;
    isTimerVisible = false;
    stopTimer();
    final file = File(_saveFileName);
    if (file.existsSync()) file.deleteSync();
    _autoSave();
  }

  void activateJolly(int gameIndex, int teamIndex) {
    if (teamIndex < teams.length && !teams[teamIndex].hasUsedJolly) {
      games[gameIndex].activeJollies[teamIndex] = true;
      teams[teamIndex].hasUsedJolly = true;
      _autoSave();
    }
  }

  void revokeJolly(int teamIndex) {
    if (teamIndex < teams.length) {
      teams[teamIndex].hasUsedJolly = false;
      for (var game in games) {
        game.activeJollies[teamIndex] = false;
      }
      _autoSave();
    }
  }

  void updateScore(int gameIndex, int teamIndex, int points) {
    games[gameIndex].scores[teamIndex] = points;
    _autoSave();
  }

  void updatePartial(int gameIndex, int teamIndex, String partialValue) {
    games[gameIndex].partials[teamIndex] = partialValue;
    _autoSave();
  }

  void navigateTo(String page) {
    if (currentPage != page) {
      currentPage = page;
      if (isRevealMode) revealedTeamsCount = 0;
      _autoSave();
    }
  }

  int getTotalScore(int teamIndex) {
    return games.fold(0, (sum, game) => sum + (game.scores[teamIndex] ?? 0));
  }
}