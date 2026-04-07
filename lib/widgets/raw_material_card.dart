import 'package:flutter/material.dart';
import 'package:produktion_planer/models/raw_material.dart';
import 'package:produktion_planer/services/database_service.dart';

class RawMaterialCard extends StatefulWidget {
  final RawMaterial rawMaterial;

  const RawMaterialCard({super.key, required this.rawMaterial});

  @override
  State<RawMaterialCard> createState() => _RawMaterialCardState();
}

class _RawMaterialCardState extends State<RawMaterialCard> {
  late bool _ordered;

  @override
  void initState() {
    super.initState();
    _ordered = widget.rawMaterial.ordered;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: CheckboxListTile(
        title: Text(widget.rawMaterial.name),
        subtitle: Text(widget.rawMaterial.quantity),
        value: _ordered,
        onChanged: (value) async {
          if (value == null) return;
          await DatabaseService.instance.updateRawMaterialOrder(widget.rawMaterial.id!, value);
          setState(() {
            _ordered = value;
          });
        },
        secondary: Icon(
          _ordered ? Icons.check_circle : Icons.error_outline,
          color: _ordered ? Colors.green : Colors.red,
        ),
      ),
    );
  }
}
