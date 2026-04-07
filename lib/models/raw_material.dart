class RawMaterial {
  final int? id;
  final int productId;
  final String name;
  final String quantity;
  final bool ordered;

  RawMaterial({
    this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.ordered,
  });

  factory RawMaterial.fromMap(Map<String, Object?> map) {
    return RawMaterial(
      id: map['id'] as int?,
      productId: map['productId'] as int,
      name: map['name'] as String,
      quantity: map['quantity'] as String,
      ordered: (map['ordered'] as int) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'productId': productId,
      'name': name,
      'quantity': quantity,
      'ordered': ordered ? 1 : 0,
    };
  }
}
