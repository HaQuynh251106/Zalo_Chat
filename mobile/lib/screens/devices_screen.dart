import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/me/devices') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _devices = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _logoutDevice(Map<String, dynamic> device) async {
    final api = context.read<ApiClient>();
    final auth = context.read<AuthProvider>();
    final id = device['id'] as String;
    try {
      await api.delete('/me/devices/$id');
      if (!mounted) return;
      if (id == auth.deviceId) {
        await auth.logout(remote: false);
        return;
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _logoutAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất tất cả thiết bị?'),
        content: const Text('Bạn sẽ cần đăng nhập lại trên mọi thiết bị.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<ApiClient>().delete('/me/devices');
      if (!mounted) return;
      await context.read<AuthProvider>().logout(remote: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        title: const Text('Thiết bị đăng nhập'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    ..._devices.map(_deviceTile),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _logoutAll,
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất tất cả thiết bị'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> device) {
    final current = (device['current'] ?? false) as bool;
    final name = (device['device_name'] ?? '') as String;
    final platform = (device['platform'] ?? '') as String;
    final lastSeen = DateTime.parse(device['last_seen_at'] as String).toLocal();
    final df = DateFormat('dd/MM HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppPalette.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.devices_other_outlined,
                color: AppPalette.indigo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Thiết bị Lumo' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${platform.isEmpty ? 'unknown' : platform} • hoạt động ${df.format(lastSeen)}',
                  style: const TextStyle(
                      color: AppPalette.textSecondary, fontSize: 12),
                ),
                if (current)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text('Thiết bị hiện tại',
                        style:
                            TextStyle(color: AppPalette.coral, fontSize: 12)),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Đăng xuất thiết bị',
            onPressed: () => _logoutDevice(device),
            icon: const Icon(Icons.logout, color: Colors.red),
          ),
        ],
      ),
    );
  }
}
