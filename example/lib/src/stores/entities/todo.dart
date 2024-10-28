class Todo {
  final int id;
  final String text;
  final bool done;

  Todo({
    required this.id,
    required this.text,
    required this.done,
  });

  Todo copyWith({String? text, bool? done}) {
    return Todo(
      id: id,
      text: text ?? this.text,
      done: done ?? this.done,
    );
  }

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable)
  // or [freezed](https://pub.dev/packages/freezed) already for your models
  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'text': text,
      'done': done,
    };
  }

  static Todo fromJSON(Map<String, dynamic> json) {
    return Todo(
      id: json['id'],
      text: json['text'],
      done: json['done'],
    );
  }
}
