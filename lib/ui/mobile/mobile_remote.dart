import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileRemoteScreen extends StatefulWidget {
  const MobileRemoteScreen({super.key});

  @override
  State<MobileRemoteScreen> createState() => _MobileRemoteScreenState();
}

class _MobileRemoteScreenState extends State<MobileRemoteScreen> {
  String serverIp = '';
  bool isConnected = false;
  
  List<dynamic> teams = [];
  List<dynamic> games = [];
  
  int? lastGameId; 
  
  bool isTimerVisible = false;
  int timerSeconds = 0;
  bool isTimerRunning = false;
  
  // --- NUOVA VARIABILE PER SAPERE SE LO STREAMING È ATTIVO ---
  bool isStreamingActive = false;
  
  Timer? _pollingTimer;

  final TextEditingController ipCtrl = TextEditingController();
  final TextEditingController timerMinCtrl = TextEditingController(text: "5");
  final TextEditingController timerSecCtrl = TextEditingController(text: "0");

  Map<int, TextEditingController> scoreCtrls = {};
  Map<int, TextEditingController> partialCtrls = {};
  
  Map<int, String> savedScores = {};
  Map<int, String> savedPartials = {};

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('saved_server_ip');
    if (savedIp != null && savedIp.isNotEmpty) {
      setState(() {
        ipCtrl.text = savedIp;
      });
    }
  }

  void _connectToServer() async {
    if (ipCtrl.text.isNotEmpty) {
      final ip = ipCtrl.text.trim();
      setState(() {
        serverIp = ip;
      });
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_server_ip', ip);

      fetchState().then((_) {
        if (isConnected) {
          _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) => fetchState(silent: true));
        }
      });
    }
  }

  Future<void> fetchState({bool silent = false}) async {
    try {
      final url = Uri.parse('https://$serverIp:8080/api/state');
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          isConnected = true;
          teams = data['teams'];
          games = data['games'];
          
          isTimerVisible = data['isTimerVisible'] ?? false;
          timerSeconds = data['timerSeconds'] ?? 0;
          isTimerRunning = data['isTimerRunning'] ?? false;
          
          isStreamingActive = data['isStreamingActive'] ?? false;
          
          String activePage = data['currentPage'];
          int? parsedPage = int.tryParse(activePage);
          
          // --- 1. RILEVIAMO SE IL GIOCO È CAMBIATO ---
          int? newGameId = lastGameId;
          if (parsedPage != null && games.any((g) => g['id'] == parsedPage)) {
            newGameId = parsedPage;
          } else if (lastGameId == null && games.isNotEmpty) {
            newGameId = games.first['id'];
          }

          bool gameChanged = newGameId != lastGameId;
          lastGameId = newGameId;

          if (lastGameId != null) {
            var currentGame = games.firstWhere((g) => g['id'] == lastGameId, orElse: () => null);
            if (currentGame != null) {
              var scores = currentGame['scores'] ?? {};
              var partials = currentGame['partials'] ?? {};

              for (var t in teams) {
                int id = t['id'];
                if (!scoreCtrls.containsKey(id)) scoreCtrls[id] = TextEditingController();
                if (!partialCtrls.containsKey(id)) partialCtrls[id] = TextEditingController();

                String sScore = (scores[id.toString()] ?? 0).toString();
                String sPartial = (partials[id.toString()] ?? '').toString();

                // --- 2. LOGICA INTELLIGENTE DI AGGIORNAMENTO TESTI ---
                // Dobbiamo aggiornare i campi di testo se:
                // - Non è silenzioso (prima connessione)
                // - Il gioco è cambiato da un altro dispositivo
                // - L'utente non sta digitando nulla di nuovo (il testo locale combacia con il vecchio testo salvato)
                
                String currentScoreInBox = scoreCtrls[id]!.text;
                if (currentScoreInBox.isEmpty) currentScoreInBox = "0";
                
                bool isUserTypingScore = currentScoreInBox != (savedScores[id] ?? "0");
                bool isUserTypingPartial = partialCtrls[id]!.text != (savedPartials[id] ?? "");

                if (!silent || gameChanged || !isUserTypingScore) {
                  scoreCtrls[id]!.text = sScore;
                }
                if (!silent || gameChanged || !isUserTypingPartial) {
                  partialCtrls[id]!.text = sPartial;
                }

                savedScores[id] = sScore;
                savedPartials[id] = sPartial;
              }
            }
          }
        });
      }
    } catch (e) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile connettersi al server.')));
        setState(() => isConnected = false);
      }
    }
  }

  Future<void> sendCommand(String endpoint) async {
    final url = Uri.parse('https://$serverIp:8080$endpoint');
    try {
      await http.post(url);
      fetchState(silent: true);
    } catch (e) {}
  }

  Future<void> saveAll() async {
    if (lastGameId == null) return;
    List<Future> futures = [];
    
    for (var t in teams) {
      int id = t['id'];
      
      String currentScore = scoreCtrls[id]?.text ?? "0";
      if (currentScore.isEmpty) currentScore = "0";
      if (currentScore != savedScores[id]) {
        futures.add(http.post(Uri.parse('https://$serverIp:8080/api/score?game=$lastGameId&team=$id&points=$currentScore')));
      }
      
      String currentPartial = partialCtrls[id]?.text ?? "";
      if (currentPartial != savedPartials[id]) {
        String encodedVal = Uri.encodeComponent(currentPartial);
        futures.add(http.post(Uri.parse('https://$serverIp:8080/api/partial?game=$lastGameId&team=$id&value=$encodedVal')));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modifiche Salvate!'), backgroundColor: Colors.green));
      fetchState(); 
    }
  }

  int _getTotaleSquadra(int teamId) {
    int total = 0;
    for (var g in games) {
      if (g['scores'] != null && g['scores'][teamId.toString()] != null) {
        total += (g['scores'][teamId.toString()] as num).toInt();
      }
    }
    return total;
  }

  String get formattedTimer {
    String m = (timerSeconds ~/ 60).toString().padLeft(2, '0');
    String s = (timerSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('📱 Associa Tabellone'), backgroundColor: Colors.blueGrey),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 20),
              const Text("Inserisci l'IP del computer che fa da tabellone (es. 192.168.1.50):", textAlign: TextAlign.center),
              const SizedBox(height: 10),
              TextField(
                controller: ipCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '192.168.x.x'),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _connectToServer,
                icon: const Icon(Icons.link), label: const Text("Connetti"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              )
            ],
          ),
        ),
      );
    }

    bool hasUnsavedChanges = false;
    if (lastGameId != null) {
      for (var t in teams) {
        int id = t['id'];
        String cs = scoreCtrls[id]?.text ?? "0";
        if (cs.isEmpty) cs = "0";
        if (cs != savedScores[id]) hasUnsavedChanges = true;
        if ((partialCtrls[id]?.text ?? "") != savedPartials[id]) hasUnsavedChanges = true;
      }
    }

    var currentGame = games.firstWhere((g) => g['id'] == lastGameId, orElse: () => null);
    String gameName = currentGame != null ? currentGame['name'] : 'Nessun gioco selezionato';

    return Scaffold(
      // --- QUI GESTIAMO IL BOTTONE DELLA VIDEOCAMERA / STOP ---
      appBar: AppBar(
        title: const Text('Arbitro Mobile'),
        backgroundColor: Colors.blueGrey,
        actions: [
          isStreamingActive
          ? IconButton(
              icon: const Icon(Icons.videocam_off, color: Colors.redAccent), 
              tooltip: 'Forza chiusura Diretta',
              onPressed: () async {
                bool confirm = await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('🛑 Stop Streaming', style: TextStyle(color: Colors.red)),
                    content: const Text('Forzare la chiusura dello streaming video attivo su tutti i dispositivi?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Termina'),
                      ),
                    ],
                  )
                ) ?? false;
                if (confirm) sendCommand('/api/stream/stop');
              }
            )
          : IconButton(
              icon: const Icon(Icons.videocam, color: Colors.amberAccent), 
              tooltip: 'Avvia Diretta Video',
              onPressed: () async {
                final url = Uri.parse('https://$serverIp:8080/stream_broadcaster.html');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () {
            _pollingTimer?.cancel();
            setState(() { isConnected = false; });
          })
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: hasUnsavedChanges ? Colors.green : Colors.grey.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: Icon(hasUnsavedChanges ? Icons.save : Icons.check_circle),
          label: Text(hasUnsavedChanges ? 'SALVA' : 'SALVATO', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          onPressed: hasUnsavedChanges ? saveAll : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.amber.shade50,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text('⏱️ TIMER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange)),
                  Text(formattedTimer, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.play_circle_fill, size: 40, color: Colors.green), onPressed: isTimerRunning ? null : () => sendCommand('/api/timer/start')),
                      IconButton(icon: const Icon(Icons.stop_circle, size: 40, color: Colors.red), onPressed: !isTimerRunning ? null : () => sendCommand('/api/timer/stop')),
                      IconButton(icon: const Icon(Icons.refresh, size: 40, color: Colors.grey), onPressed: () => sendCommand('/api/timer/reset')),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: timerMinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min', isDense: true))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: timerSecCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sec', isDense: true))),
                      const SizedBox(width: 10),
                      ElevatedButton(onPressed: () => sendCommand('/api/timer/set?m=${timerMinCtrl.text}&s=${timerSecCtrl.text}'), child: const Text('Set'))
                    ],
                  )
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 15),
          
          Text('🎮 MODIFICANDO: ${gameName.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
          const SizedBox(height: 10),

          ...teams.map((team) {
            int teamId = team['id'];
            bool hasUsedJolly = team['hasUsedJolly'] == true;
            
            Color teamColor = Colors.white;
            try { teamColor = Color(int.parse(team['colorHex'].substring(1), radix: 16) + 0xFF000000); } catch (e) {}

            String currentScore = scoreCtrls[teamId]?.text ?? "0";
            if (currentScore.isEmpty) currentScore = "0";
            bool isScoreSaved = currentScore == savedScores[teamId];
            bool isPartialSaved = (partialCtrls[teamId]?.text ?? "") == savedPartials[teamId];

            return Card(
              color: teamColor.withOpacity(0.1),
              shape: RoundedRectangleBorder(side: BorderSide(color: teamColor.withOpacity(0.5), width: 2), borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(team['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('🏆 Totale Gen: ${_getTotaleSquadra(teamId)} pt', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.indigo)),
                            ],
                          )
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasUsedJolly ? Colors.grey : Colors.orange, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                          ), 
                          onPressed: () {
                             if (hasUsedJolly) sendCommand('/api/jolly/revoke?team=$teamId');
                             else sendCommand('/api/jolly?game=$lastGameId&team=$teamId');
                          }, 
                          child: Text(hasUsedJolly ? 'Jolly Usato' : '🌟 Jolly')
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: scoreCtrls[teamId], 
                            keyboardType: TextInputType.number, 
                            onChanged: (val) => setState(() {}),
                            style: TextStyle(color: isScoreSaved ? Colors.black : Colors.red, fontWeight: isScoreSaved ? FontWeight.normal : FontWeight.bold),
                            decoration: const InputDecoration(labelText: 'Punti', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white)
                          )
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: partialCtrls[teamId], 
                            onChanged: (val) => setState(() {}),
                            style: TextStyle(color: isPartialSaved ? Colors.black : Colors.red, fontWeight: isPartialSaved ? FontWeight.normal : FontWeight.bold),
                            decoration: const InputDecoration(labelText: 'Parziale / Note', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white)
                          )
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}