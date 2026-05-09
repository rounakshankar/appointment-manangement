import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_toast.dart';

class ExportTextScreen extends StatefulWidget {
  const ExportTextScreen({
    super.key,
    required this.apiClient,
    required this.title,
    required this.endpoint,
  });

  final ApiClient apiClient;
  final String title;
  final String endpoint;

  @override
  State<ExportTextScreen> createState() => _ExportTextScreenState();
}

class _ExportTextScreenState extends State<ExportTextScreen> {
  String? _text;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await widget.apiClient.dio.get<String>(widget.endpoint);
      if (mounted) {
        setState(() {
          _text = resp.data ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: 'Failed to load export', type: ToastType.error);
      }
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text ?? ''));
    if (mounted) AppToast.show(context, message: 'Copied', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        title: Text(widget.title, style: AppTypography.heading3.copyWith(color: AppColors.surface)),
        actions: [
          IconButton(
            onPressed: _text == null ? null : _copy,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _text ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
