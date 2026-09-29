import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../api.dart';
import '../auth_store.dart';
import '../theme.dart';
import 'account.dart';
import 'doc_detail.dart';
import 'login.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> _docs = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await Api.listDocuments();
      if (!mounted) return;
      setState(() => _docs = list);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await AuthStore.clear();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your library.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read file bytes.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final doc = await Api.uploadPdf(f.name, bytes);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DocDetailScreen(docId: doc['id'] as int)),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Upload failed.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this PDF?'),
        content: const Text('The file, summary, and chat history will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteDocument(id);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your library'),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _docs.isEmpty
                ? _EmptyState(uploading: _uploading, error: _error, onUpload: _upload)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _docs.length + 1,
                    separatorBuilder: (_, i) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return _UploadCard(busy: _uploading, error: _error, onTap: _upload);
                      }
                      final d = _docs[i - 1] as Map<String, dynamic>;
                      return _DocRow(
                        doc: d,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => DocDetailScreen(docId: d['id'] as int)),
                        ),
                        onDelete: () => _delete(d['id'] as int),
                      );
                    },
                  ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final bool busy;
  final String? error;
  final VoidCallback onTap;
  const _UploadCard({required this.busy, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upload a PDF', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Up to 50 MB. We summarize it and let you chat with it.',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file, color: oxfordBlue),
          ],
        ),
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  const _DocRow({required this.doc, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = doc['status'] as String;
    final pages = doc['page_count'] as int? ?? 0;
    final created = DateTime.tryParse(doc['created_at'] as String? ?? '');
    final dateStr = created != null ? DateFormat('MMM d, y').format(created.toLocal()) : '';
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    _StatusChip(status: status),
                    const SizedBox(width: 8),
                    Text(
                      pages > 0 ? '$pages pages · $dateStr' : dateStr,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ]),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: inkSoft, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ready' => ('Ready', brandGreen),
      'failed' => ('Failed', Colors.redAccent),
      _ => (_titleCase(status), oxfordBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _EmptyState extends StatelessWidget {
  final bool uploading;
  final String? error;
  final VoidCallback onUpload;
  const _EmptyState({required this.uploading, required this.error, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Text('No PDFs yet', style: Theme.of(context).textTheme.displayMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Upload your first PDF to get a summary and chat with it.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: inkSoft),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: uploading ? null : onUpload,
            icon: uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 18),
            label: Text(uploading ? 'Uploading…' : 'Upload PDF'),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
        ],
      ],
    );
  }
}
