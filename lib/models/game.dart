class Game {
  String name;
  Map<int, int> scores = {};
  Map<int, String> partials = {};
  Map<int, bool> activeJollies = {};

  Game({required this.name});

  Map<String, dynamic> toJson() => {
    'name': name,
    'scores': scores.map((key, value) => MapEntry(key.toString(), value)),
    'partials': partials.map((key, value) => MapEntry(key.toString(), value)),
    'activeJollies': activeJollies.map((key, value) => MapEntry(key.toString(), value)),
  };

  factory Game.fromJson(Map<String, dynamic> json) {
    var game = Game(name: json['name']);
    
    if (json['scores'] != null) {
      game.scores = (json['scores'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as int));
    }
    if (json['partials'] != null) {
      game.partials = (json['partials'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as String));
    }
    if (json['activeJollies'] != null) {
      game.activeJollies = (json['activeJollies'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as bool));
    }
    return game;
  }
}