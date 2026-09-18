import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_theme.dart';

class CodeSnippetDialog extends StatefulWidget {
  final void Function(String code, String language) onSend;

  const CodeSnippetDialog({super.key, required this.onSend});

  @override
  State<CodeSnippetDialog> createState() => _CodeSnippetDialogState();
}

class _CodeSnippetDialogState extends State<CodeSnippetDialog> {
  final TextEditingController _codeController = TextEditingController();
  String _selectedLanguage = 'dart';

  final List<String> _languages = [
    'dart',
    'python',
    'javascript',
    'typescript',
    'go',
    'rust',
    'json',
    'yaml',
    'bash',
    'sql',
    'html',
    'css',
    'c',
    'cpp',
    'java',
    'kotlin',
  ];

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DevSyncColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DevSyncColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.integration_instructions_rounded, color: DevSyncColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Share Code Snippet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: DevSyncColors.textPrimary,
                  ),
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: _selectedLanguage,
                  dropdownColor: DevSyncColors.surfaceVariant,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: DevSyncColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                  items: _languages.map((lang) {
                    return DropdownMenuItem(
                      value: lang,
                      child: Text(lang.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLanguage = val);
                  },
                ),
              ],
            ),
            const Divider(height: 20),

            // Code Editor
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: DevSyncColors.codeBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DevSyncColors.border),
                ),
                child: TextField(
                  controller: _codeController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: DevSyncColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '// Paste or type your code here...',
                    hintStyle: const TextStyle(color: DevSyncColors.textMuted, fontFamily: 'monospace'),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.all(12),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste_rounded, size: 18, color: DevSyncColors.textSecondary),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _codeController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: DevSyncColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final code = _codeController.text;
                    if (code.trim().isNotEmpty) {
                      widget.onSend(code, _selectedLanguage);
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DevSyncColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
