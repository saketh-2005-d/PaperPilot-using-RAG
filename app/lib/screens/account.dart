import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../api.dart';
import '../auth_store.dart';
import '../theme.dart';
import 'login.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _me;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await Api.getMe();
      if (!mounted) return;
      setState(() => _me = me);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _afterSignedOut();
        return;
      }
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your account.');
    }
  }

  Future<void> _afterSignedOut() async {
    await AuthStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await _afterSignedOut();
  }

  Future<void> _deleteAccount() async {
    final email = _me?['email'] as String? ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: Text(
          'This permanently removes $email, every PDF you uploaded, '
          'their summaries, and your chat history. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Api.deleteMe();
      await _afterSignedOut();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete the account.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: _me == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _AccountBody(me: _me!, onSignOut: _signOut, onDelete: _deleteAccount),
    );
  }
}

class _AccountBody extends StatelessWidget {
  final Map<String, dynamic> me;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;
  const _AccountBody({required this.me, required this.onSignOut, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final email = me['email'] as String;
    final docs = me['document_count'] as int? ?? 0;
    final created = DateTime.tryParse(me['created_at'] as String? ?? '');
    final since = created != null ? DateFormat('MMM y').format(created.toLocal()) : '—';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: oxfordBlue, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(email, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('Member since $since', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _StatRow(label: 'Documents', value: '$docs'),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
          label: const Text('Delete account', style: TextStyle(color: Colors.redAccent)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEED7D7))),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
