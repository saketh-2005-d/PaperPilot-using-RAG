import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdfrx/pdfrx.dart';

import '../api.dart';
import '../theme.dart';

class DocDetailScreen extends StatefulWidget {
  final int docId;
  const DocDetailScreen({super.key, required this.docId});

  @override
  State<DocDetailScreen> createState() => _DocDetailScreenState();
}

class _DocDetailScreenState extends State<DocDetailScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _doc;
  String? _error;
  Timer? _poll;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_doc != null && (_doc!['status'] == 'ready' || _doc!['status'] == 'failed')) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final d = await Api.getDocument(widget.docId);
      if (!mounted) return;
      setState(() => _doc = d);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?['title'] as String? ?? 'Loading…', maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
            child: TabBar(
              controller: _tabs,
              labelColor: oxfordBlue,
              unselectedLabelColor: inkSoft,
              indicatorColor: oxfordBlue,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [Tab(text: 'Summary'), Tab(text: 'PDF'), Tab(text: 'Chat')],
            ),
          ),
        ),
      ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _SummaryTab(doc: d),
                _PdfTab(docId: widget.docId),
                ChatTab(docId: widget.docId, ready: d['status'] == 'ready'),
              ],
            ),
    );
  }
}

class _PdfTab extends StatefulWidget {
  final int docId;
  const _PdfTab({required this.docId});

  @override
  State<_PdfTab> createState() => _PdfTabState();
}

class _PdfTabState extends State<_PdfTab> {
  String? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final url = await Api.getPdfUrl(widget.docId);
      if (!mounted) return;
      setState(() => _url = url);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (_url == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PdfViewer.uri(
      Uri.parse(_url!),
      params: const PdfViewerParams(
        margin: 8,
        backgroundColor: paper,
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _SummaryTab({required this.doc});

  @override
  Widget build(BuildContext context) {
    final status = doc['status'] as String;
    if (status != 'ready') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == 'failed') ...[
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
                const SizedBox(height: 12),
                Text(
                  doc['error'] as String? ?? 'Failed to process this PDF.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_label(status), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text('This may take a minute or two.',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ],
          ),
        ),
      );
    }

    final tldr = doc['summary_tldr'] as String? ?? '';
    final sections = (doc['sections'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('TL;DR', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        _md(tldr),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        for (final s in sections) ...[
          Text(s['section'] as String? ?? '',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: oxfordBlue)),
          const SizedBox(height: 6),
          _md(s['summary'] as String? ?? ''),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  static Widget _md(String text) => MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(fontSize: 15, height: 1.55, color: ink),
          h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink),
          h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
          h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
          listBullet: const TextStyle(fontSize: 15, color: ink),
          tableBody: const TextStyle(fontSize: 14, color: ink),
          tableHead: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
          blockquote: const TextStyle(fontSize: 15, color: inkSoft, fontStyle: FontStyle.italic),
          code: const TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: Color(0xFFF1F1EC)),
        ),
      );

  static String _label(String status) => switch (status) {
        'uploading' => 'Uploading…',
        'extracting' => 'Reading the PDF…',
        'embedding' => 'Indexing for chat…',
        'summarizing' => 'Summarizing…',
        _ => 'Processing…',
      };
}

class ChatTab extends StatefulWidget {
  final int docId;
  final bool ready;
  const ChatTab({super.key, required this.docId, required this.ready});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _msgs = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Api.listMessages(widget.docId);
      if (!mounted) return;
      setState(() {
        _msgs = m;
        _loading = false;
      });
      _scrollToEnd();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _msgs = [
        ..._msgs,
        {'role': 'user', 'content': text, 'citations': []},
      ];
      _sending = true;
    });
    _scrollToEnd();
    try {
      final res = await Api.chat(widget.docId, text);
      if (!mounted) return;
      setState(() {
        _msgs = [
          ..._msgs,
          {'role': 'assistant', 'content': res['answer'], 'citations': res['citations'] ?? []},
        ];
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs = [
          ..._msgs,
          {'role': 'assistant', 'content': '_${e.message}_', 'citations': []},
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs = [
          ..._msgs,
          {'role': 'assistant', 'content': '_Could not reach the server._', 'citations': []},
        ];
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Chat unlocks when the PDF is ready.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: inkSoft),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _msgs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Ask anything about this PDF.',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: inkSoft),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(16),
                        itemCount: _msgs.length + (_sending ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _msgs.length) return const _Typing();
                          final m = _msgs[i] as Map<String, dynamic>;
                          return _Bubble(message: m);
                        },
                      ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask about this PDF',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.arrow_upward),
                  style: IconButton.styleFrom(
                    backgroundColor: oxfordBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final citations = (message['citations'] as List?) ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? oxfordBlue : Colors.white,
                border: isUser ? null : Border.all(color: line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isUser
                  ? Text(
                      message['content'] as String,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                    )
                  : MarkdownBody(
                      data: message['content'] as String,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 15, height: 1.55, color: ink),
                        h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
                        h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
                        listBullet: const TextStyle(fontSize: 15, color: ink),
                        tableBody: const TextStyle(fontSize: 14, color: ink),
                        tableHead: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
                        code: const TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: Color(0xFFF1F1EC)),
                      ),
                    ),
            ),
          ),
          if (!isUser && citations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in citations)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: brandGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'p. ${c['page_start']}–${c['page_end']}',
                      style: const TextStyle(color: brandGreen, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 28,
          height: 14,
          child: Center(
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ),
    );
  }
}
