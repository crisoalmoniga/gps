import 'package:flutter/material.dart';

import '../models/incident_report.dart';

class ReportDetailResult {
  final String? incidentType;
  final String? severity;
  final String? description;

  const ReportDetailResult({this.incidentType, this.severity, this.description});
}

/// Formulario opcional y no bloqueante para agregar detalle a un reporte que
/// ya fue creado con el boton de 1 tap (seccion 0 del spec).
Future<ReportDetailResult?> showReportDetailSheet(BuildContext context) {
  String? incidentType;
  String? severity;
  final descriptionController = TextEditingController();

  return showModalBottomSheet<ReportDetailResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '¿Queres agregar detalle? (opcional)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tu reporte ya se guardo. Esto es solo para dar mas contexto.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Tipo de incidente'),
                  initialValue: incidentType,
                  items: kIncidentTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))))
                      .toList(),
                  onChanged: (value) => setState(() => incidentType = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Gravedad'),
                  initialValue: severity,
                  items: kSeverityLevels
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (value) => setState(() => severity = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripcion (opcional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Omitir'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(
                          ReportDetailResult(
                            incidentType: incidentType,
                            severity: severity,
                            description: descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                          ),
                        ),
                        child: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
