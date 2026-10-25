import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/ai_config.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final Map<String, String?> _masked = {};
  final Map<String, bool> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMasked());
  }

  Future<void> _loadMasked() async {
    final config = await ref.read(aiConfigProvider.future);
    final secure = ref.read(secureStoreProvider);
    for (final provider in config.providers) {
      final masked = await secure.maskedKey(provider.id);
      if (!mounted) return;
      setState(() => _masked[provider.id] = masked);
    }
  }

  Future<void> _setKey(ProviderConfig provider) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${provider.label} API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'sk-…',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Stored in the Android Keystore on this phone only. It is never '
              'logged and never leaves the device except to the provider.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (key == null || key.isEmpty) return;
    await ref.read(secureStoreProvider).writeKey(provider.id, key);
    await _loadMasked();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${provider.label} key saved')));
  }

  Future<void> _testKey(ProviderConfig provider) async {
    final config = await ref.read(aiConfigProvider.future);
    final key = await ref.read(secureStoreProvider).readKey(provider.id);
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a key first.')),
      );
      return;
    }
    setState(() => _busy[provider.id] = true);
    try {
      final roleConfig = config.roles.firstWhere(
        (role) => role.providerId == provider.id,
        orElse: () => RoleConfig(
          role: BotRole.writer,
          providerId: provider.id,
          model: provider.kind.defaultModel,
        ),
      );
      final reply = await ref.read(llmClientProvider).testProvider(
            provider: provider,
            model: roleConfig.model,
            apiKey: key,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${provider.label}: $reply')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${provider.label}: $error')));
    } finally {
      if (mounted) setState(() => _busy[provider.id] = false);
    }
  }

  Future<void> _editRole(RoleConfig role, AiConfig config) async {
    final providerController = StateController(role.providerId);
    final modelController = TextEditingController(text: role.model);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(BotRole.labels[role.role] ?? role.role),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: config.providers
                      .any((p) => p.id == role.providerId)
                  ? role.providerId
                  : null,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final provider in config.providers)
                  DropdownMenuItem(
                    value: provider.id,
                    child: Text(provider.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) providerController.value = value;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: const InputDecoration(labelText: 'Model id'),
            ),
            const SizedBox(height: 10),
            Text(
              BotRole.hints[role.role] ?? '',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    modelController.dispose();
    if (saved != true) return;
    await ref.read(aiConfigProvider.notifier).setRole(
          role.copyWith(
            providerId: providerController.value,
            model: modelController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configAsync = ref.watch(aiConfigProvider);
    final config = configAsync.valueOrNull ?? AiConfig.defaults();
    final usage = ref.watch(usageTotalsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI settings'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionCard(
            title: 'Usage',
            subtitle: 'This device only.',
            child: Row(
              children: [
                _Metric(label: 'Calls', value: '${usage['calls'] ?? 0}'),
                _Metric(label: 'In', value: '${usage['input'] ?? 0}'),
                _Metric(label: 'Out', value: '${usage['output'] ?? 0}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Providers',
            subtitle: 'Add a key for at least one. Keys stay on this phone.',
            child: Column(
              children: [
                for (final provider in config.providers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(provider.label),
                    subtitle: Text(
                      _masked[provider.id] == null
                          ? 'No key'
                          : 'Key ${_masked[provider.id]}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy[provider.id] ?? false)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            tooltip: 'Test',
                            onPressed: () => _testKey(provider),
                            icon: const Icon(Icons.network_check, size: 20),
                          ),
                        IconButton(
                          tooltip: 'Set key',
                          onPressed: () => _setKey(provider),
                          icon: const Icon(Icons.key, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Delete key',
                          onPressed: () async {
                            await ref
                                .read(secureStoreProvider)
                                .deleteKey(provider.id);
                            await _loadMasked();
                          },
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Per-role models',
            subtitle: 'Tap a role to change its provider or model id.',
            child: Column(
              children: [
                for (final role in config.roles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(BotRole.labels[role.role] ?? role.role),
                    subtitle: Text(
                      '${config.provider(role.providerId)?.label ?? role.providerId}'
                      ' · ${role.model}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Switch(
                      value: role.enabled,
                      onChanged: (value) => ref
                          .read(aiConfigProvider.notifier)
                          .setRole(role.copyWith(enabled: value)),
                    ),
                    onTap: () => _editRole(role, config),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Fallback order',
            subtitle: 'Tried in order when a provider fails or has no key.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final role in config.roles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${BotRole.labels[role.role] ?? role.role}: '
                      '${[
                        role.model,
                        ...role.fallbacks.map((f) => f.model),
                      ].join(' → ')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(aiConfigProvider.notifier).reset();
                    await _loadMasked();
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reset all routing to defaults'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// Minimal stand-in for a ValueNotifier of strings.
class StateController extends ValueNotifier<String> {
  StateController(super.value);
}
