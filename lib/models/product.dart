class Product {
  final int? id;
  final String articleNumber;
  final String name;
  final int plannedQuantity;
  final String? machineSettings;
  final double averageDurationPerUnit;
  final String? parameterHistory;

  Product({
    this.id,
    required this.articleNumber,
    required this.name,
    required this.plannedQuantity,
    this.machineSettings,
    required this.averageDurationPerUnit,
    this.parameterHistory,
  });

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as int?,
      articleNumber: map['articleNumber'] as String,
      name: map['name'] as String,
      plannedQuantity: map['plannedQuantity'] as int,
      machineSettings: map['machineSettings'] as String?,
      averageDurationPerUnit: (map['averageDurationPerUnit'] as num).toDouble(),
      parameterHistory: map['parameterHistory'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'articleNumber': articleNumber,
      'name': name,
      'plannedQuantity': plannedQuantity,
      'machineSettings': machineSettings,
      'averageDurationPerUnit': averageDurationPerUnit,
      'parameterHistory': parameterHistory,
    };
  }
}
