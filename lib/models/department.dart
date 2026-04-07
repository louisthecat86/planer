class Department {
  final int id;
  final String name;
  final int color;
  final String shortCode;

  Department({required this.id, required this.name, required this.color, required this.shortCode});

  factory Department.fromMap(Map<String, Object?> map) {
    return Department(
      id: map['id'] as int,
      name: map['name'] as String,
      color: map['color'] as int,
      shortCode: map['shortCode'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'shortCode': shortCode,
    };
  }
}
