import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../repositories/user_profile_repository.dart';
import '../widgets/forest_background.dart';

class ChooseUsernameScreen extends StatefulWidget {
  final bool allowSkip;
  final VoidCallback? onSkip;
  final VoidCallback? onSaved;

  const ChooseUsernameScreen({
    super.key,
    this.allowSkip = false,
    this.onSkip,
    this.onSaved,
  });

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final UserProfileRepository _repository = UserProfileRepository.instance;
  final TextEditingController _usernameController = TextEditingController();

  UserProfile? _profile;
  String? _errorText;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_validate);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _repository.ensureUserProfile();
    if (!mounted) return;
    final suggested = profile?.username ?? _suggestUsername(profile);
    if (suggested != null && suggested.isNotEmpty) {
      _usernameController.text = suggested;
    }
    setState(() {
      _profile = profile;
      _loading = false;
      _errorText = UserProfileRepository.validateUsername(
        _usernameController.text.trim(),
      );
    });
  }

  String? _suggestUsername(UserProfile? profile) {
    final displayName = profile?.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      return null;
    }
    final compact = displayName
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (compact.length < 3) {
      return null;
    }
    return compact.length > 20 ? compact.substring(0, 20) : compact;
  }

  void _validate() {
    final message = UserProfileRepository.validateUsername(
      _usernameController.text.trim(),
    );
    if (message == _errorText) {
      return;
    }
    setState(() => _errorText = message);
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final username = _usernameController.text.trim();
    final validation = UserProfileRepository.validateUsername(username);
    if (validation != null) {
      setState(() => _errorText = validation);
      return;
    }

    setState(() => _saving = true);
    try {
      await _repository.claimUsername(username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username saved.')),
      );
      final onSaved = widget.onSaved;
      if (onSaved != null) {
        onSaved();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } on UsernameTakenException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
    } on UsernameValidationException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Could not save username. Check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _skip() {
    final onSkip = widget.onSkip;
    if (onSkip != null) {
      onSkip();
      return;
    }
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentTextColor = Color(0xCCFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Username'),
        backgroundColor: const Color(0xFF1F4E3D),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: !widget.allowSkip,
      ),
      body: ForestBackground(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        includeTopSafeArea: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _profile?.hasUsername == true
                            ? 'Edit your public username'
                            : 'Choose your public username',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your username may appear beside public observations. Email addresses are never used for this.',
                        style: TextStyle(
                          color: accentTextColor,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _usernameController,
                        enabled: !_saving,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Username',
                          helperText: '3-20 letters, numbers, or underscores',
                          errorText: _errorText,
                          labelStyle: const TextStyle(color: accentTextColor),
                          helperStyle: const TextStyle(color: accentTextColor),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving || _errorText != null
                              ? null
                              : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8FBFA1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(_saving ? 'Saving...' : 'Save Username'),
                        ),
                      ),
                      if (widget.allowSkip) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _saving ? null : _skip,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Skip for now'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
